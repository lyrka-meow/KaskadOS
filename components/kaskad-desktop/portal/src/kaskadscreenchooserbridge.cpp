/*
    SPDX-License-Identifier: LGPL-2.0-or-later
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
*/

#include "kaskadscreenchooserbridge.h"
#include "screenchooserdialog.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QUuid>

using namespace Qt::StringLiterals;

KaskadScreenChooserBridge::KaskadScreenChooserBridge(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().registerObject(
        u"/org/kaskados/ScreenCastChooser1"_s,
        this,
        QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
}

KaskadScreenChooserBridge *KaskadScreenChooserBridge::self()
{
    static auto bridge = new KaskadScreenChooserBridge;
    return bridge;
}

bool KaskadScreenChooserBridge::request(ScreenChooserDialog *dialog, const QString &title, const QString &optionsJson)
{
    const auto bus = QDBusConnection::sessionBus().interface();
    if (!bus || !bus->isServiceRegistered(u"org.kaskados.Shell1"_s)) {
        return false;
    }

    const QString requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_requests.insert(requestId, dialog);
    connect(dialog, &QObject::destroyed, this, [this, dialog] {
        forget(dialog);
    });
    Q_EMIT selectionRequested(requestId, title, optionsJson);
    return true;
}

void KaskadScreenChooserBridge::forget(ScreenChooserDialog *dialog)
{
    for (auto it = m_requests.begin(); it != m_requests.end();) {
        if (it.value() == dialog) {
            it = m_requests.erase(it);
        } else {
            ++it;
        }
    }
}

bool KaskadScreenChooserBridge::select(const QString &requestId, const QString &kind, const QString &id, bool allowRestore)
{
    if (!isKaskadCaller()) {
        return false;
    }
    ScreenChooserDialog *dialog = m_requests.take(requestId);
    if (!dialog || !dialog->selectExternal(kind, id, allowRestore)) {
        return false;
    }
    dialog->accept();
    return true;
}

bool KaskadScreenChooserBridge::cancel(const QString &requestId)
{
    if (!isKaskadCaller()) {
        return false;
    }
    ScreenChooserDialog *dialog = m_requests.take(requestId);
    if (!dialog) {
        return false;
    }
    dialog->reject();
    return true;
}

bool KaskadScreenChooserBridge::isKaskadCaller() const
{
    if (!calledFromDBus()) {
        return true;
    }
    const auto bus = QDBusConnection::sessionBus().interface();
    if (!bus) {
        return false;
    }
    return bus->serviceOwner(u"org.kaskados.Shell1"_s).value() == message().service();
}
