/*
 * SPDX-License-Identifier: LGPL-2.0-or-later
 * SPDX-FileCopyrightText: 2026 KaskadOS contributors
 */

#pragma once

#include <QHash>
#include <QDBusAbstractAdaptor>
#include <QVariantMap>

class QDBusPendingCallWatcher;

class NotificationPortal : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Notification")
    Q_CLASSINFO("D-Bus Introspection", "  <interface name=\"org.freedesktop.impl.portal.Notification\">\n"
                                      "    <method name=\"AddNotification\">\n"
                                      "      <arg direction=\"in\" type=\"s\" name=\"app_id\"/>\n"
                                      "      <arg direction=\"in\" type=\"s\" name=\"id\"/>\n"
                                      "      <arg direction=\"in\" type=\"a{sv}\" name=\"notification\"/>\n"
                                      "    </method>\n"
                                      "    <method name=\"RemoveNotification\">\n"
                                      "      <arg direction=\"in\" type=\"s\" name=\"app_id\"/>\n"
                                      "      <arg direction=\"in\" type=\"s\" name=\"id\"/>\n"
                                      "    </method>\n"
                                      "    <property access=\"read\" type=\"a{sv}\" name=\"SupportedOptions\"/>\n"
                                      "    <signal name=\"ActionInvoked\">\n"
                                      "      <arg type=\"s\" name=\"app_id\"/>\n"
                                      "      <arg type=\"s\" name=\"id\"/>\n"
                                      "      <arg type=\"s\" name=\"action\"/>\n"
                                      "      <arg type=\"av\" name=\"parameter\"/>\n"
                                      "    </signal>\n"
                                      "    <property access=\"read\" type=\"u\" name=\"version\"/>\n"
                                      "  </interface>\n")
    Q_PROPERTY(QVariantMap SupportedOptions READ supportedOptions CONSTANT)
    Q_PROPERTY(uint version READ version CONSTANT)

public:
    explicit NotificationPortal(QObject *parent);

    QVariantMap supportedOptions() const;
    uint version() const;

public Q_SLOTS:
    void AddNotification(const QString &appId, const QString &id, const QVariantMap &notification);
    void RemoveNotification(const QString &appId, const QString &id);

Q_SIGNALS:
    void ActionInvoked(const QString &appId, const QString &id, const QString &action, const QVariantList &parameter);

private Q_SLOTS:
    void notificationClosed(uint notificationId, uint reason);
    void actionInvoked(uint notificationId, const QString &actionKey);
    void activationToken(uint notificationId, const QString &token);

private:
    struct Action {
        QString name;
        QVariant target;
    };

    struct Notification {
        QString appId;
        QString id;
        uint serverId = 0;
        quint64 generation = 0;
        Action defaultAction;
        QHash<QString, Action> actions;
        QString activationToken;
    };

    static QString key(const QString &appId, const QString &id);
    static QString applicationObjectPath(const QString &appId);
    void activate(const Notification &notification, const Action &action);
    void forget(const QString &key);

    QHash<QString, Notification> m_notifications;
    QHash<uint, QString> m_serverIds;
    quint64 m_generation = 0;
};
