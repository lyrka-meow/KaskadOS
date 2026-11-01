/*
    SPDX-FileCopyrightText: 2016 Martin Graesslin <mgraesslin@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

*/
#include "osd.h"
#include "kaskadipc.h"
#include "workspace.h"

#include <QThread>

namespace KWin
{
namespace OSD
{

void show(const QString &message, const QString &iconName, int timeout)
{
    if (QThread::currentThread() != qGuiApp->thread()) {
        QTimer::singleShot(0, QCoreApplication::instance(), [message, iconName, timeout] {
            show(message, iconName, timeout);
        });
        return;
    }

    if (auto *ipc = workspace()->findChild<KaskadIpc *>()) {
        Q_EMIT ipc->messageRequested(message, iconName, timeout);
    }
}

void show(const QString &message, int timeout)
{
    show(message, QString(), timeout);
}

void show(const QString &message, const QString &iconName)
{
    show(message, iconName, 0);
}

void hide(HideFlags flags)
{
    Q_UNUSED(flags)
    if (auto *ipc = workspace()->findChild<KaskadIpc *>()) {
        Q_EMIT ipc->messageHideRequested();
    }
}

}
}
