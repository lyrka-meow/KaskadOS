/*
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
    SPDX-License-Identifier: GPL-3.0-or-later
*/

#pragma once

#include <QDBusServiceWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

class KaskadIpcClient : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Kaskad)
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(uint protocolVersion READ protocolVersion NOTIFY versionsChanged)
    Q_PROPERTY(QString compositorVersion READ compositorVersion NOTIFY versionsChanged)
    Q_PROPERTY(QVariantMap activeWindow READ activeWindow NOTIFY activeWindowChanged)
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
    Q_PROPERTY(QVariantList outputs READ outputs NOTIFY outputsChanged)
    Q_PROPERTY(QVariantList workspaces READ workspaces NOTIFY workspacesChanged)
    Q_PROPERTY(QVariantList keyboardLayouts READ keyboardLayouts NOTIFY keyboardLayoutsChanged)
    Q_PROPERTY(QVariantList availableKeyboardLayouts READ availableKeyboardLayouts NOTIFY availableKeyboardLayoutsChanged)
    Q_PROPERTY(uint currentKeyboardLayout READ currentKeyboardLayout NOTIFY keyboardLayoutsChanged)
    Q_PROPERTY(QString keyboardLayoutShortcut READ keyboardLayoutShortcut NOTIFY keyboardLayoutShortcutChanged)
    Q_PROPERTY(QString screenshotShortcut READ screenshotShortcut NOTIFY screenshotShortcutChanged)
    Q_PROPERTY(QString microphoneShortcut READ microphoneShortcut NOTIFY microphoneShortcutChanged)

public:
    explicit KaskadIpcClient(QObject *parent = nullptr);

    bool available() const;
    uint protocolVersion() const;
    QString compositorVersion() const;
    QVariantMap activeWindow() const;
    QVariantList windows() const;
    QVariantList outputs() const;
    QVariantList workspaces() const;
    QVariantList keyboardLayouts() const;
    QVariantList availableKeyboardLayouts() const;
    uint currentKeyboardLayout() const;
    QString keyboardLayoutShortcut() const;
    QString screenshotShortcut() const;
    QString microphoneShortcut() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool activateWorkspace(const QString &id);
    Q_INVOKABLE bool activateWorkspaceOnOutput(const QString &id, const QString &outputName);
    Q_INVOKABLE bool assignWorkspaceToOutput(const QString &id, const QString &outputName);
    Q_INVOKABLE QString createWorkspace(uint position, const QString &name = QString());
    Q_INVOKABLE QString createWorkspaceForOutput(uint position, const QString &name, const QString &outputName);
    Q_INVOKABLE bool removeWorkspace(const QString &id);
    Q_INVOKABLE bool renameWorkspace(const QString &id, const QString &name);
    Q_INVOKABLE bool activateWindow(const QString &id);
    Q_INVOKABLE bool closeWindow(const QString &id);
    Q_INVOKABLE bool respondToUnresponsiveWindow(const QString &id, bool forceClose);
    Q_INVOKABLE bool respondToWindowActionPrompt(const QString &id, const QString &action, bool undo, bool dontShowAgain = false);
    Q_INVOKABLE bool setWindowMinimized(const QString &id, bool minimized);
    Q_INVOKABLE bool setWindowFullscreen(const QString &id, bool fullscreen);
    Q_INVOKABLE bool moveWindowToWorkspace(const QString &windowId, const QString &workspaceId);
    Q_INVOKABLE QString outputAtCursor() const;
    Q_INVOKABLE bool setPrimaryOutput(const QString &outputName);
    Q_INVOKABLE bool applyOutputConfiguration(const QVariantList &outputs);
    Q_INVOKABLE bool setKeyboardLayouts(const QStringList &layouts);
    Q_INVOKABLE bool setCurrentKeyboardLayout(uint index);
    Q_INVOKABLE bool setKeyboardLayoutShortcut(const QString &shortcut);
    Q_INVOKABLE bool resetKeyboardLayoutShortcut();
    Q_INVOKABLE bool submitScreenCastSelection(const QString &requestId, const QString &kind, const QString &id, bool allowRestore = true);
    Q_INVOKABLE bool cancelScreenCastSelection(const QString &requestId);
    Q_INVOKABLE bool setScreenshotShortcut(const QString &shortcut);
    Q_INVOKABLE bool setScreenshotProfiles(const QVariantList &profiles);
    Q_INVOKABLE bool setMicrophoneShortcut(const QString &shortcut);
    Q_INVOKABLE void setShortcutCaptureActive(bool active);
    Q_INVOKABLE QStringList pressedShortcutModifiers() const;
    Q_INVOKABLE QVariantMap decorationPalette() const;
    Q_INVOKABLE bool setDecorationPalette(const QVariantMap &palette);
    Q_INVOKABLE bool setCursorAccent(const QString &accent);
    Q_INVOKABLE void requestScreenshot();

Q_SIGNALS:
    void availableChanged();
    void versionsChanged();
    void activeWindowChanged();
    void windowsChanged();
    void outputsChanged();
    void workspacesChanged();
    void keyboardLayoutsChanged();
    void availableKeyboardLayoutsChanged();
    void keyboardLayoutShortcutChanged();
    void overviewRequested(const QString &reason);
    void messageRequested(const QString &message, const QString &iconName, int timeout);
    void messageHideRequested();
    void windowMenuRequested(const QString &windowId, int x, int y);
    void unresponsiveWindowRequested(const QString &windowId, const QString &title, const QString &appId, const QString &outputName);
    void unresponsiveWindowDismissed(const QString &windowId);
    void windowActionPromptRequested(const QString &windowId, const QString &title, const QString &action, const QString &outputName, const QString &shortcut, const QString &shortcutSource);
    void windowActionPromptDismissed(const QString &windowId, const QString &action);
    void screenCastSelectionRequested(const QString &requestId, const QString &title, const QString &optionsJson);
    void screenshotRequested();
    void screenshotProfileRequested(const QString &profileId);
    void screenshotShortcutChanged();
    void microphoneShortcutChanged();
    void microphoneShortcutKeyChanged(bool pressed);
    void shortcutCaptured(const QString &shortcut);

private Q_SLOTS:
    void handleServiceRegistered();
    void handleServiceUnregistered();
    void handleWindowAdded(const QString &id);
    void handleWindowRemoved(const QString &id);
    void handleWindowChanged(const QString &id, const QStringList &fields);
    void handleActiveWindowChanged(const QString &id);
    void handleOutputsChanged();
    void handleWorkspacesChanged();
    void refreshOutputs();
    void refreshWorkspaces();
    void refreshTopology();
    void refreshKeyboardLayouts();
    void handleOverviewRequested(const QString &reason);
    void handleScreenCastSelectionRequested(const QString &requestId, const QString &title, const QString &optionsJson);
    void handleKeyboardLayoutShortcutChanged(const QString &shortcut);
    void handleScreenshotShortcutChanged(const QString &shortcut);
    void handleMicrophoneShortcutChanged(const QString &shortcut);

private:
    QVariant call(const QString &method, const QVariantList &arguments = {}) const;
    void refreshVersions();
    void refreshWindows();
    void refreshActiveWindow();
    void clear();

    static constexpr auto Service = "org.kaskados.Compositor1";
    static constexpr auto Path = "/org/kaskados/Compositor1";
    static constexpr auto Interface = "org.kaskados.Compositor1";

    QDBusServiceWatcher m_watcher;
    bool m_available = false;
    uint m_protocolVersion = 0;
    QString m_compositorVersion;
    QVariantMap m_activeWindow;
    QVariantList m_windows;
    QVariantList m_outputs;
    QVariantList m_workspaces;
    QVariantList m_keyboardLayouts;
    QVariantList m_availableKeyboardLayouts;
    uint m_currentKeyboardLayout = 0;
    QString m_keyboardLayoutShortcut;
    QString m_screenshotShortcut;
    QString m_microphoneShortcut;
};
