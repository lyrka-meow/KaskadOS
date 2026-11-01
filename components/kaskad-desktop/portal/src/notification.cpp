/*
 * SPDX-License-Identifier: LGPL-2.0-or-later
 * SPDX-FileCopyrightText: 2026 KaskadOS contributors
 */

#include "notification.h"

#include "portalicon.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QFileInfo>

using namespace Qt::StringLiterals;

namespace
{
constexpr auto notificationService = "org.freedesktop.Notifications";
constexpr auto notificationPath = "/org/freedesktop/Notifications";
constexpr auto notificationInterface = "org.freedesktop.Notifications";

QVariant unwrap(const QVariant &value)
{
    return value.metaType() == QMetaType::fromType<QDBusVariant>() ? value.value<QDBusVariant>().variant() : value;
}

QVariantMap variantMap(const QVariant &value)
{
    const QVariant unwrapped = unwrap(value);
    if (unwrapped.canConvert<QVariantMap>()) {
        return unwrapped.toMap();
    }
    if (unwrapped.metaType() == QMetaType::fromType<QDBusArgument>()) {
        return qdbus_cast<QVariantMap>(unwrapped.value<QDBusArgument>());
    }
    return {};
}

QList<QVariantMap> buttonMaps(const QVariant &value)
{
    const QVariant unwrapped = unwrap(value);
    QList<QVariantMap> result;
    if (unwrapped.canConvert<QVariantList>()) {
        for (const QVariant &entry : unwrapped.toList()) {
            const QVariantMap map = variantMap(entry);
            if (!map.isEmpty()) {
                result.append(map);
            }
        }
        return result;
    }
    if (unwrapped.metaType() == QMetaType::fromType<QDBusArgument>()) {
        QDBusArgument argument = unwrapped.value<QDBusArgument>();
        argument.beginArray();
        while (!argument.atEnd()) {
            QVariantMap map;
            argument >> map;
            if (!map.isEmpty()) {
                result.append(map);
            }
        }
        argument.endArray();
    }
    return result;
}

QString iconName(const QVariant &value)
{
    const QVariant unwrapped = unwrap(value);
    if (unwrapped.metaType() != QMetaType::fromType<QDBusArgument>()) {
        return {};
    }

    const PortalIcon icon = qdbus_cast<PortalIcon>(unwrapped.value<QDBusArgument>());
    const QVariant data = unwrap(icon.data.variant());
    if (icon.str == u"themed"_s) {
        const QStringList names = data.toStringList();
        return names.value(0);
    }
    if (icon.str == u"file"_s) {
        const QString path = data.toString();
        return QFileInfo(path).isAbsolute() ? path : QString();
    }
    return {};
}

uchar urgency(const QString &priority)
{
    if (priority == u"low"_s) {
        return 0;
    }
    if (priority == u"urgent"_s) {
        return 2;
    }
    return 1;
}
}

NotificationPortal::NotificationPortal(QObject *parent)
    : QDBusAbstractAdaptor(parent)
{
    PortalIcon::registerDBusType();
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QString::fromLatin1(notificationService), QString::fromLatin1(notificationPath), QString::fromLatin1(notificationInterface),
                u"NotificationClosed"_s, this, SLOT(notificationClosed(uint,uint)));
    bus.connect(QString::fromLatin1(notificationService), QString::fromLatin1(notificationPath), QString::fromLatin1(notificationInterface),
                u"ActionInvoked"_s, this, SLOT(actionInvoked(uint,QString)));
    bus.connect(QString::fromLatin1(notificationService), QString::fromLatin1(notificationPath), QString::fromLatin1(notificationInterface),
                u"ActivationToken"_s, this, SLOT(activationToken(uint,QString)));
}

QVariantMap NotificationPortal::supportedOptions() const
{
    return {};
}

uint NotificationPortal::version() const
{
    return 2;
}

QString NotificationPortal::key(const QString &appId, const QString &id)
{
    return appId + QChar::Null + id;
}

QString NotificationPortal::applicationObjectPath(const QString &appId)
{
    QString path = u'/' + appId;
    path.replace(u'.', u'/');
    path.replace(u'-', u'_');
    return path;
}

void NotificationPortal::AddNotification(const QString &appId, const QString &id, const QVariantMap &payload)
{
    const QString notificationKey = key(appId, id);
    Notification &tracked = m_notifications[notificationKey];
    tracked.appId = appId;
    tracked.id = id;
    tracked.generation = ++m_generation;
    tracked.defaultAction = {payload.value(u"default-action"_s).toString(), unwrap(payload.value(u"default-action-target"_s))};
    tracked.actions.clear();

    QStringList actions;
    if (!tracked.defaultAction.name.isEmpty()) {
        actions << u"default"_s << QString();
    }

    qsizetype buttonIndex = 0;
    for (const QVariantMap &button : buttonMaps(payload.value(u"buttons"_s))) {
        const QString actionName = button.value(u"action"_s).toString();
        const QString label = button.value(u"label"_s).toString();
        if (actionName.isEmpty() || label.isEmpty()) {
            continue;
        }
        const QString actionKey = u"portal-action-%1"_s.arg(buttonIndex++);
        tracked.actions.insert(actionKey, {actionName, unwrap(button.value(u"target"_s))});
        actions << actionKey << label;
    }

    QVariantMap hints{
        {u"desktop-entry"_s, appId},
        {u"urgency"_s, QVariant::fromValue(urgency(payload.value(u"priority"_s, u"normal"_s).toString()))},
    };
    const QStringList displayHints = payload.value(u"display-hint"_s).toStringList();
    if (displayHints.contains(u"transient"_s)) {
        hints.insert(u"transient"_s, true);
    }
    if (!payload.value(u"category"_s).toString().isEmpty()) {
        hints.insert(u"category"_s, payload.value(u"category"_s).toString());
    }
    if (!payload.value(u"sound-name"_s).toString().isEmpty()) {
        hints.insert(u"sound-name"_s, payload.value(u"sound-name"_s).toString());
    }

    QDBusMessage message = QDBusMessage::createMethodCall(QString::fromLatin1(notificationService), QString::fromLatin1(notificationPath),
                                                           QString::fromLatin1(notificationInterface), u"Notify"_s);
    message.setArguments({appId,
                          tracked.serverId,
                          iconName(payload.value(u"icon"_s)),
                          payload.value(u"title"_s).toString(),
                          payload.value(u"body"_s).toString(),
                          actions,
                          hints,
                          -1});

    const quint64 generation = tracked.generation;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, notificationKey, generation]() {
        const QDBusPendingReply<uint> reply = *watcher;
        watcher->deleteLater();
        auto iterator = m_notifications.find(notificationKey);
        if (iterator == m_notifications.end() || iterator->generation != generation) {
            if (!reply.isError() && reply.value() != 0) {
                QDBusMessage close = QDBusMessage::createMethodCall(QString::fromLatin1(notificationService), QString::fromLatin1(notificationPath),
                                                                    QString::fromLatin1(notificationInterface), u"CloseNotification"_s);
                close.setArguments({reply.value()});
                QDBusConnection::sessionBus().call(close, QDBus::NoBlock);
            }
            return;
        }
        if (reply.isError()) {
            m_notifications.erase(iterator);
            return;
        }
        if (iterator->serverId != 0) {
            m_serverIds.remove(iterator->serverId);
        }
        iterator->serverId = reply.value();
        m_serverIds.insert(iterator->serverId, notificationKey);
    });
}

void NotificationPortal::RemoveNotification(const QString &appId, const QString &id)
{
    const QString notificationKey = key(appId, id);
    const auto iterator = m_notifications.constFind(notificationKey);
    if (iterator == m_notifications.cend()) {
        return;
    }
    const uint serverId = iterator->serverId;
    forget(notificationKey);
    if (serverId != 0) {
        QDBusMessage close = QDBusMessage::createMethodCall(QString::fromLatin1(notificationService), QString::fromLatin1(notificationPath),
                                                            QString::fromLatin1(notificationInterface), u"CloseNotification"_s);
        close.setArguments({serverId});
        QDBusConnection::sessionBus().call(close, QDBus::NoBlock);
    }
}

void NotificationPortal::notificationClosed(uint notificationId, uint reason)
{
    Q_UNUSED(reason)
    const QString notificationKey = m_serverIds.value(notificationId);
    if (!notificationKey.isEmpty()) {
        forget(notificationKey);
    }
}

void NotificationPortal::actionInvoked(uint notificationId, const QString &actionKey)
{
    const QString notificationKey = m_serverIds.value(notificationId);
    auto iterator = m_notifications.find(notificationKey);
    if (iterator == m_notifications.end()) {
        return;
    }
    const Notification notification = iterator.value();
    const Action action = actionKey == u"default"_s ? notification.defaultAction : notification.actions.value(actionKey);
    if (!action.name.isEmpty()) {
        activate(notification, action);
    }
    forget(notificationKey);
}

void NotificationPortal::activationToken(uint notificationId, const QString &token)
{
    const QString notificationKey = m_serverIds.value(notificationId);
    auto iterator = m_notifications.find(notificationKey);
    if (iterator != m_notifications.end()) {
        iterator->activationToken = token;
    }
}

void NotificationPortal::activate(const Notification &notification, const Action &action)
{
    QVariantMap platformData;
    if (!notification.activationToken.isEmpty()) {
        platformData.insert(u"activation-token"_s, notification.activationToken);
        platformData.insert(u"desktop-startup-id"_s, notification.activationToken);
    }

    if (action.name.startsWith(u"app."_s)) {
        QVariantList parameters;
        if (action.target.isValid()) {
            parameters << action.target;
        }
        QDBusMessage message = QDBusMessage::createMethodCall(notification.appId, applicationObjectPath(notification.appId),
                                                               u"org.freedesktop.Application"_s, u"ActivateAction"_s);
        message.setArguments({action.name.mid(4), parameters, platformData});
        QDBusConnection::sessionBus().call(message, QDBus::NoBlock);
        return;
    }

    QVariantList parameters;
    if (action.target.isValid()) {
        parameters << action.target;
    }
    parameters << platformData;
    Q_EMIT ActionInvoked(notification.appId, notification.id, action.name, parameters);
}

void NotificationPortal::forget(const QString &notificationKey)
{
    const auto iterator = m_notifications.find(notificationKey);
    if (iterator == m_notifications.end()) {
        return;
    }
    if (iterator->serverId != 0) {
        m_serverIds.remove(iterator->serverId);
    }
    m_notifications.erase(iterator);
}

#include "moc_notification.cpp"
