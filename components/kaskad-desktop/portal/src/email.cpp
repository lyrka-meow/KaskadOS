/*
 * SPDX-FileCopyrightText: 2017 Red Hat Inc
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 *
 * SPDX-FileCopyrightText: 2017 Jan Grulich <jgrulich@redhat.com>
 */

#include "email.h"
#include "email_debug.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QProcess>
#include <QUrl>

EmailPortal::EmailPortal(QObject *parent)
    : QDBusAbstractAdaptor(parent)
{
}

void EmailPortal::ComposeEmail(const QDBusObjectPath &handle,
                               const QString &app_id,
                               const QString &window,
                               const QVariantMap &options,
                               const QDBusMessage &message,
                               uint &replyResponse,
                               [[maybe_unused]] QVariantMap &replyResults)
{
    qCDebug(XdgDesktopPortalKdeEmail) << "ComposeEmail called with parameters:";
    qCDebug(XdgDesktopPortalKdeEmail) << "    handle: " << handle.path();
    qCDebug(XdgDesktopPortalKdeEmail) << "    app_id: " << app_id;
    qCDebug(XdgDesktopPortalKdeEmail) << "    window: " << window;
    qCDebug(XdgDesktopPortalKdeEmail) << "    options: " << options;

    const QStringList addresses = options.contains(QStringLiteral("address")) ? options.value(QStringLiteral("address")).toStringList()
                                                                              : options.value(QStringLiteral("addresses")).toStringList();

    Q_UNUSED(message)

    QStringList arguments;
    const auto appendValues = [&arguments](const QString &option, const QStringList &values) {
        for (const QString &value : values) {
            arguments << option << value;
        }
    };
    appendValues(QStringLiteral("--cc"), options.value(QStringLiteral("cc")).toStringList());
    appendValues(QStringLiteral("--bcc"), options.value(QStringLiteral("bcc")).toStringList());
    appendValues(QStringLiteral("--attach"), options.value(QStringLiteral("attachments")).toStringList());
    if (const QString subject = options.value(QStringLiteral("subject")).toString(); !subject.isEmpty()) {
        arguments << QStringLiteral("--subject") << subject;
    }
    if (const QString body = options.value(QStringLiteral("body")).toString(); !body.isEmpty()) {
        arguments << QStringLiteral("--body") << body;
    }
    arguments << addresses;

    replyResponse = QProcess::startDetached(QStringLiteral("xdg-email"), arguments) ? 0u : 2u;
}

#include "moc_email.cpp"
