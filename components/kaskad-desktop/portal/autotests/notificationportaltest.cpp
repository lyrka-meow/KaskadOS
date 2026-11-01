/*
 * SPDX-License-Identifier: LGPL-2.0-or-later
 * SPDX-FileCopyrightText: 2026 KaskadOS contributors
 */

#include "notification.h"

#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QSignalSpy>
#include <QTest>

class FakeNotificationServer : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

public:
    explicit FakeNotificationServer(QObject *parent)
        : QDBusAbstractAdaptor(parent)
    {
    }

    void invoke(uint id, const QString &action)
    {
        Q_EMIT ActionInvoked(id, action);
    }

public Q_SLOTS:
    uint Notify(const QString &appName,
                uint replacesId,
                const QString &appIcon,
                const QString &summary,
                const QString &body,
                const QStringList &actions,
                const QVariantMap &hints,
                int timeout)
    {
        Q_UNUSED(timeout)
        lastAppName = appName;
        lastReplacesId = replacesId;
        lastAppIcon = appIcon;
        lastSummary = summary;
        lastBody = body;
        lastActions = actions;
        lastHints = hints;
        Q_EMIT notified();
        return 41;
    }

    void CloseNotification(uint id)
    {
        Q_EMIT closed(id);
    }

Q_SIGNALS:
    void notified();
    void closed(uint id);
    void NotificationClosed(uint id, uint reason);
    void ActionInvoked(uint id, const QString &action);
    void ActivationToken(uint id, const QString &token);

public:
    QString lastAppName;
    uint lastReplacesId = 0;
    QString lastAppIcon;
    QString lastSummary;
    QString lastBody;
    QStringList lastActions;
    QVariantMap lastHints;
};

class NotificationPortalTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(QDBusConnection::sessionBus().isConnected());
        QVERIFY(QDBusConnection::sessionBus().registerService(QStringLiteral("org.freedesktop.Notifications")));
        QVERIFY(QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/freedesktop/Notifications"), &m_serverObject,
                                                             QDBusConnection::ExportAdaptors));
    }

    void forwardsNotificationAndAction()
    {
        QObject portalObject;
        NotificationPortal portal(&portalObject);
        QSignalSpy notifiedSpy(&m_server, &FakeNotificationServer::notified);
        QSignalSpy actionSpy(&portal, &NotificationPortal::ActionInvoked);

        const QVariantMap button{
            {QStringLiteral("label"), QStringLiteral("Open")},
            {QStringLiteral("action"), QStringLiteral("open")},
            {QStringLiteral("target"), QStringLiteral("message-7")},
        };
        const QVariantMap notification{
            {QStringLiteral("title"), QStringLiteral("Incoming")},
            {QStringLiteral("body"), QStringLiteral("Hello")},
            {QStringLiteral("priority"), QStringLiteral("urgent")},
            {QStringLiteral("buttons"), QVariantList{button}},
        };

        portal.AddNotification(QStringLiteral("org.kaskados.Test"), QStringLiteral("message"), notification);
        QTRY_COMPARE(notifiedSpy.count(), 1);
        QCOMPARE(m_server.lastAppName, QStringLiteral("org.kaskados.Test"));
        QCOMPARE(m_server.lastSummary, QStringLiteral("Incoming"));
        QCOMPARE(m_server.lastBody, QStringLiteral("Hello"));
        QCOMPARE(m_server.lastActions, QStringList({QStringLiteral("portal-action-0"), QStringLiteral("Open")}));
        QCOMPARE(m_server.lastHints.value(QStringLiteral("desktop-entry")).toString(), QStringLiteral("org.kaskados.Test"));
        QCOMPARE(m_server.lastHints.value(QStringLiteral("urgency")).value<uchar>(), uchar(2));

        // Let the asynchronous Notify reply populate the server-id mapping.
        QTRY_VERIFY(QDBusConnection::sessionBus().isConnected());
        QTest::qWait(20);
        m_server.invoke(41, QStringLiteral("portal-action-0"));
        QTRY_COMPARE(actionSpy.count(), 1);
        const QList<QVariant> actionArguments = actionSpy.takeFirst();
        QCOMPARE(actionArguments.at(0).toString(), QStringLiteral("org.kaskados.Test"));
        QCOMPARE(actionArguments.at(1).toString(), QStringLiteral("message"));
        QCOMPARE(actionArguments.at(2).toString(), QStringLiteral("open"));
        const QVariantList parameters = actionArguments.at(3).toList();
        QCOMPARE(parameters.value(0).toString(), QStringLiteral("message-7"));
        QCOMPARE(parameters.value(1).toMap(), QVariantMap());
    }

private:
    QObject m_serverObject;
    FakeNotificationServer m_server{&m_serverObject};
};

QTEST_GUILESS_MAIN(NotificationPortalTest)

#include "notificationportaltest.moc"

