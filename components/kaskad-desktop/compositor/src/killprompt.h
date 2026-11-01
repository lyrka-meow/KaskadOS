/*
 * SPDX-FileCopyrightText: 2023 Kai Uwe Broulik <kde@broulik.de>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

#include <QtTypes>

namespace KWin
{

class Window;

class KillPrompt
{
public:
    /**
     * @brief Creates a shell-owned unresponsive-window request.
     * @param window The window to kill, must be an X11Window or XdgToplevelWindow.
     */
    explicit KillPrompt(Window *window);

    /**
     * @brief Whether the shell still has an active request for this window.
     */
    bool isRunning() const;

    /**
     * @brief Asks the KaskadOS shell to show the force-close confirmation.
     * @param timestamp The X activation timestamp.
     */
    void start(quint32 timestamp = 0);
    /**
     * @brief Withdraw the shell request when the application responds again.
     */
    void quit();

private:
    Window *m_window = nullptr;
};

} // namespace KWin
