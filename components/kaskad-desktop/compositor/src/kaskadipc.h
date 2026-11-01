/*
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QAction>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>

#include "effect/globals.h"
#include "input_event.h"
#include "input_event_spy.h"

namespace KWin
{

class Window;
class Workspace;

class KaskadIpc : public QObject, public InputEventSpy
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kaskados.Compositor1")

public:
    explicit KaskadIpc(Workspace *workspace);
    ~KaskadIpc() override;

public Q_SLOTS:
    uint protocolVersion() const;
    QString compositorVersion() const;
    QVariantMap activeWindow() const;
    QVariantList windows() const;
    QVariantList outputs() const;
    QVariantMap topology() const;
    QString topologyJson() const;
    bool setPrimaryOutput(const QString &outputName);
    bool applyOutputConfiguration(const QVariantList &outputs);
    bool applyOutputConfigurationJson(const QString &outputsJson);
    QString outputAtCursor() const;
    QVariantList workspaces() const;
    QVariantList keyboardLayouts() const;
    QVariantList availableKeyboardLayouts() const;
    uint currentKeyboardLayout() const;
    bool setKeyboardLayouts(const QStringList &layouts);
    bool setCurrentKeyboardLayout(uint index);
    QString keyboardLayoutShortcut() const;
    bool setKeyboardLayoutShortcut(const QString &shortcut);
    bool resetKeyboardLayoutShortcut();
    bool activateWorkspace(const QString &id);
    bool activateWorkspaceOnOutput(const QString &id, const QString &outputName);
    bool assignWorkspaceToOutput(const QString &id, const QString &outputName);
    QString createWorkspace(uint position, const QString &name);
    QString createWorkspaceForOutput(uint position, const QString &name, const QString &outputName);
    bool removeWorkspace(const QString &id);
    bool renameWorkspace(const QString &id, const QString &name);
    bool activateWindow(const QString &id);
    bool closeWindow(const QString &id);
    bool respondToLogoutConfirmation(bool logoutAnyway);
    bool respondToUnresponsiveWindow(const QString &id, bool forceClose);
    bool respondToWindowActionPrompt(const QString &id, const QString &action, bool undo, bool dontShowAgain);
    bool setWindowMinimized(const QString &id, bool minimized);
    bool setWindowFullscreen(const QString &id, bool fullscreen);
    bool moveWindowToWorkspace(const QString &windowId, const QString &workspaceId);
    void requestOverview(const QString &reason = QStringLiteral("ipc"));
    QString screenshotShortcut() const;
    bool setScreenshotShortcut(const QString &shortcut);
    bool setScreenshotProfilesJson(const QString &profilesJson);
    QString microphoneShortcut() const;
    bool setMicrophoneShortcut(const QString &shortcut);
    void setShortcutCaptureActive(bool active);
    QStringList pressedShortcutModifiers() const;
    QVariantMap screenshotShortcutDebug() const;
    QVariantMap decorationPalette() const;
    bool setDecorationPalette(const QVariantMap &palette);
    bool setCursorAccent(const QString &accent);
    void requestScreenshot();
    bool toggleHoveredWindowBorder();

    void requestUnresponsiveWindowAction(Window *window);
    void dismissUnresponsiveWindowRequest(Window *window);
    bool hasUnresponsiveWindowRequest(const Window *window) const;
    void requestWindowActionPrompt(Window *window, const QString &action);
    void dismissWindowActionPrompt(Window *window, const QString &action);
    bool hasWindowActionPrompt(const Window *window, const QString &action) const;

private Q_SLOTS:
    bool overviewBorderActivated(ElectricBorder border);
    void handleRawKeyState(quint32 keyCode, KeyboardKeyState state);

private:
    void pointerButton(PointerButtonEvent *event) override;

Q_SIGNALS:
    void windowAdded(const QString &id);
    void windowRemoved(const QString &id);
    void windowChanged(const QString &id, const QStringList &fields);
    void activeWindowChanged(const QString &id);
    void outputsChanged();
    void workspacesChanged();
    void topologyChanged();
    void keyboardLayoutsChanged();
    void keyboardLayoutShortcutChanged(const QString &shortcut);
    void overviewRequested(const QString &reason);
    void messageRequested(const QString &message, const QString &iconName, int timeout);
    void messageHideRequested();
    void logoutConfirmationRequested(const QStringList &applications);
    void logoutConfirmationDismissed();
    void windowMenuRequested(const QString &windowId, int x, int y);
    void unresponsiveWindowRequested(const QString &windowId, const QString &title, const QString &appId, const QString &outputName);
    void unresponsiveWindowDismissed(const QString &windowId);
    void windowActionPromptRequested(const QString &windowId, const QString &title, const QString &action, const QString &outputName, const QString &shortcut, const QString &shortcutSource);
    void windowActionPromptDismissed(const QString &windowId, const QString &action);
    void screenshotRequested();
    void screenshotProfileRequested(const QString &profileId);
    void screenshotShortcutChanged(const QString &shortcut);
    void microphoneShortcutChanged(const QString &shortcut);
    void microphoneShortcutKeyChanged(bool pressed);
    void shortcutCaptured(const QString &shortcut);

private:
    void watchWindow(Window *window);
    QVariantMap windowData(const Window *window) const;
    void scheduleTopologyChanged();

    Workspace *m_workspace;
    bool m_topologyChangePending = false;
    QAction *m_screenshotAction = nullptr;
    QHash<QString, QAction *> m_screenshotProfileActions;
    QAction *m_toggleHoveredBorderAction = nullptr;
    QAction *m_overviewAction = nullptr;
    QAction *m_gridAction = nullptr;
    QAction *m_walkWindowsAction = nullptr;
    QAction *m_walkWindowsReverseAction = nullptr;
    bool m_shortcutCaptureActive = false;
    QSet<quint32> m_pressedRawKeys;
    QSet<quint32> m_captureModifierKeys;
    QSet<QString> m_unresponsiveWindowRequests;
    QHash<QString, QString> m_windowActionPrompts;
    bool m_captureSawNonModifier = false;
    QStringList m_recentRawKeyEvents;
    quint32 m_lastRawKeyCode = 0;
    KeyboardKeyState m_lastRawKeyState = KeyboardKeyState::Released;
    quint64 m_screenshotShortcutTriggerCount = 0;
    QString m_microphoneShortcut;
    quint32 m_microphonePressedKey = 0;
    quint32 m_microphonePressedMouseButton = 0;
    bool m_microphoneModifierShortcutPressed = false;
    const QString m_serviceName = QStringLiteral("org.kaskados.Compositor1");
};

} // namespace KWin
