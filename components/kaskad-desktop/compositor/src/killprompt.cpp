/*
 * SPDX-FileCopyrightText: 2023 Kai Uwe Broulik <kde@broulik.de>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "killprompt.h"

#include "kaskadipc.h"
#include "window.h"
#include "workspace.h"

namespace KWin
{

KillPrompt::KillPrompt(Window *window)
    : m_window(window)
{
    Q_ASSERT(window);
}

bool KillPrompt::isRunning() const
{
    if (auto *ipc = workspace()->findChild<KaskadIpc *>()) {
        return ipc->hasUnresponsiveWindowRequest(m_window);
    }
    return false;
}

void KillPrompt::start(quint32 timestamp)
{
    Q_UNUSED(timestamp)
    if (auto *ipc = workspace()->findChild<KaskadIpc *>()) {
        ipc->requestUnresponsiveWindowAction(m_window);
    }
}

void KillPrompt::quit()
{
    if (auto *ipc = workspace()->findChild<KaskadIpc *>()) {
        ipc->dismissUnresponsiveWindowRequest(m_window);
    }
}

} // namespace KWin
