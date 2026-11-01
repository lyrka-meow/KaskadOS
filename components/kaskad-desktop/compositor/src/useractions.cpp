/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-FileCopyrightText: 1999, 2000 Matthias Ettrich <ettrich@kde.org>
    SPDX-FileCopyrightText: 2003 Lubos Lunak <l.lunak@kde.org>
    SPDX-FileCopyrightText: 2022 Natalie Clarius <natalie_clarius@yahoo.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*

 This file contains things relevant to direct user actions, such as
 responses to global keyboard shortcuts, or selecting actions
 from the window menu.

*/

#include "config-kwin.h"

#include "core/output.h"
#include "cursor.h"
#include "input.h"
#include "kaskadipc.h"
#include "options.h"
#include "pointer_input.h"
#include "virtualdesktops.h"
#include "window.h"
#include "workspace.h"
#if KWIN_BUILD_X11
#include "x11window.h"
#endif

#include "appmenu.h"

#include <KGlobalAccel>
#include <KLocalizedString>
#include <QAction>
#include <QRegularExpression>

#include "killwindow.h"
#if KWIN_BUILD_TABBOX
#include "tabbox/tabbox.h"
#endif

namespace KWin
{


//****************************************
// Workspace
//****************************************

void Workspace::slotIncreaseWindowOpacity()
{
    if (!m_activeWindow) {
        return;
    }
    m_activeWindow->setOpacity(std::min(m_activeWindow->opacity() + 0.05, 1.0));
}

void Workspace::slotLowerWindowOpacity()
{
    if (!m_activeWindow) {
        return;
    }
    m_activeWindow->setOpacity(std::max(m_activeWindow->opacity() - 0.05, 0.05));
}


template<typename Slot>
void Workspace::initShortcut(const QString &actionName, const QString &description, const QKeySequence &shortcut, Slot slot, bool autoRepeat)
{
    initShortcut(actionName, description, shortcut, this, slot, autoRepeat);
}

template<typename T, typename Slot>
void Workspace::initShortcut(const QString &actionName, const QString &description, const QKeySequence &shortcut, T *receiver, Slot slot, bool autoRepeat)
{
    QAction *a = new QAction(this);
    a->setAutoRepeat(autoRepeat);
    a->setProperty("componentName", QStringLiteral("kwin"));
    a->setObjectName(actionName);
    a->setText(description);
    KGlobalAccel::self()->setGlobalShortcut(a, QList<QKeySequence>{shortcut});
    connect(a, &QAction::triggered, receiver, slot);
}

/**
 * Creates the global accel object \c keys.
 */
void Workspace::initShortcuts()
{
    // The first argument to initShortcut() is the id for the shortcut in the user's
    // config file, while the second argumewnt is its user-visible text.
    // Normally these should be identical, but if the user-visible text for a new
    // shortcut that you're adding is super long, it is permissible to use a shorter
    // string for name.

    // PLEASE NOTE: Never change the ID of an existing shortcut! It will cause users'
    // custom shortcuts to be lost. Instead, only change the description

    initShortcut("Window Operations Menu", i18n("Window Menu"),
                 Qt::ALT | Qt::Key_F3, &Workspace::slotWindowOperations, true);
    initShortcut("Window Close", i18n("Close Window"),
                 Qt::ALT | Qt::Key_F4, &Workspace::slotWindowClose, true);
    initShortcut("Window Maximize", i18n("Maximize Window"),
                 Qt::META | Qt::Key_PageUp, &Workspace::slotWindowMaximize, false);
    initShortcut("Window Maximize Vertical", i18n("Maximize Window Vertically"),
                 0, &Workspace::slotWindowMaximizeVertical, false);
    initShortcut("Window Maximize Horizontal", i18n("Maximize Window Horizontally"),
                 0, &Workspace::slotWindowMaximizeHorizontal, false);
    initShortcut("Window Restore", i18n("Restore Window"),
                 Qt::META | Qt::Key_Backspace, &Workspace::slotWindowRestore, true);
    initShortcut("Window Minimize", i18n("Minimize Window"),
                 Qt::META | Qt::Key_PageDown, &Workspace::slotWindowMinimize, false);
    initShortcut("Window Move", i18n("Move Window"),
                 0, &Workspace::slotWindowMove, true);
    initShortcut("Window Resize", i18n("Resize Window"),
                 0, &Workspace::slotWindowResize, true);
    initShortcut("Window Raise", i18n("Raise Window"),
                 0, &Workspace::slotWindowRaise, true);
    initShortcut("Window Lower", i18n("Lower Window"),
                 0, &Workspace::slotWindowLower, true);
    initShortcut("Toggle Window Raise/Lower", i18n("Toggle Window Raise/Lower"),
                 0, &Workspace::slotWindowRaiseOrLower, true);
    initShortcut("Window Fullscreen", i18n("Make Window Fullscreen"),
                 0, &Workspace::slotWindowFullScreen, false);
    initShortcut("Window No Border", i18n("Toggle Window Titlebar and Frame"),
                 0, &Workspace::slotWindowNoBorder, true);
    initShortcut("Window Above Other Windows", i18n("Keep Window Above Others"),
                 0, &Workspace::slotWindowAbove, true);
    initShortcut("Window Below Other Windows", i18n("Keep Window Below Others"),
                 0, &Workspace::slotWindowBelow, true);
    initShortcut("Activate Window Demanding Attention", i18n("Activate Window Demanding Attention"),
                 Qt::META | Qt::CTRL | Qt::Key_A, &Workspace::slotActivateAttentionWindow, true);
    initShortcut("Window Move Center", i18n("Move Window to the Center"), 0,
                 &Workspace::slotWindowCenter, true);
    initShortcut("Window Pack Right", i18n("Move Window Right"),
                 0, &Workspace::slotWindowMoveRight, true);
    initShortcut("Window Pack Left", i18n("Move Window Left"),
                 0, &Workspace::slotWindowMoveLeft, true);
    initShortcut("Window Pack Up", i18n("Move Window Up"),
                 0, &Workspace::slotWindowMoveUp, true);
    initShortcut("Window Pack Down", i18n("Move Window Down"),
                 0, &Workspace::slotWindowMoveDown, true);
    initShortcut("Window Grow Horizontal", i18n("Expand Window Horizontally"),
                 0, &Workspace::slotWindowExpandHorizontal, true);
    initShortcut("Window Grow Vertical", i18n("Expand Window Vertically"),
                 0, &Workspace::slotWindowExpandVertical, true);
    initShortcut("Window Shrink Horizontal", i18n("Shrink Window Horizontally"),
                 0, &Workspace::slotWindowShrinkHorizontal, true);
    initShortcut("Window Shrink Vertical", i18n("Shrink Window Vertically"),
                 0, &Workspace::slotWindowShrinkVertical, true);
    initShortcut("Window Quick Tile Left", i18n("Quick Tile Window to the Left"),
                 Qt::META | Qt::Key_Left, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Left), true);
    initShortcut("Window Quick Tile Right", i18n("Quick Tile Window to the Right"),
                 Qt::META | Qt::Key_Right, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Right), true);
    initShortcut("Window Quick Tile Top", i18n("Quick Tile Window to the Top"),
                 Qt::META | Qt::Key_Up, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Top), true);
    initShortcut("Window Quick Tile Bottom", i18n("Quick Tile Window to the Bottom"),
                 Qt::META | Qt::Key_Down, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Bottom), true);
    initShortcut("Window Quick Tile Top Left", i18n("Quick Tile Window to the Top Left"),
                 0, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Top | QuickTileFlag::Left), true);
    initShortcut("Window Quick Tile Bottom Left", i18n("Quick Tile Window to the Bottom Left"),
                 0, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Bottom | QuickTileFlag::Left), true);
    initShortcut("Window Quick Tile Top Right", i18n("Quick Tile Window to the Top Right"),
                 0, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Top | QuickTileFlag::Right), true);
    initShortcut("Window Quick Tile Bottom Right", i18n("Quick Tile Window to the Bottom Right"),
                 0, std::bind(&Workspace::quickTileWindow, this, QuickTileFlag::Bottom | QuickTileFlag::Right), true);
    initShortcut("Switch Window Up", i18n("Switch to Window Above"),
                 Qt::META | Qt::ALT | Qt::Key_Up, std::bind(static_cast<void (Workspace::*)(Direction)>(&Workspace::switchWindow), this, DirectionNorth), true);
    initShortcut("Switch Window Down", i18n("Switch to Window Below"),
                 Qt::META | Qt::ALT | Qt::Key_Down, std::bind(static_cast<void (Workspace::*)(Direction)>(&Workspace::switchWindow), this, DirectionSouth), true);
    initShortcut("Switch Window Right", i18n("Switch to Window to the Right"),
                 Qt::META | Qt::ALT | Qt::Key_Right, std::bind(static_cast<void (Workspace::*)(Direction)>(&Workspace::switchWindow), this, DirectionEast), true);
    initShortcut("Switch Window Left", i18n("Switch to Window to the Left"),
                 Qt::META | Qt::ALT | Qt::Key_Left, std::bind(static_cast<void (Workspace::*)(Direction)>(&Workspace::switchWindow), this, DirectionWest), true);
    initShortcut("Increase Opacity", i18n("Increase Opacity of Active Window by 5%"),
                 0, &Workspace::slotIncreaseWindowOpacity, true);
    initShortcut("Decrease Opacity", i18n("Decrease Opacity of Active Window by 5%"),
                 0, &Workspace::slotLowerWindowOpacity, true);

    initShortcut("Window On All Desktops", i18n("Keep Window on All Desktops"),
                 0, &Workspace::slotWindowOnAllDesktops, true);

    initShortcut("Window Custom Quick Tile Left", i18n("Custom Quick Tile Window to the Left"),
                 0, std::bind(&Workspace::customQuickTileWindow, this, QuickTileFlag::Left), true);
    initShortcut("Window Custom Quick Tile Right", i18n("Custom Quick Tile Window to the Right"),
                 0, std::bind(&Workspace::customQuickTileWindow, this, QuickTileFlag::Right), true);
    initShortcut("Window Custom Quick Tile Top", i18n("Custom Quick Tile Window to the Top"),
                 0, std::bind(&Workspace::customQuickTileWindow, this, QuickTileFlag::Top), true);
    initShortcut("Window Custom Quick Tile Bottom", i18n("Custom Quick Tile Window to the Bottom"),
                 0, std::bind(&Workspace::customQuickTileWindow, this, QuickTileFlag::Bottom), true);

    VirtualDesktopManager *vds = VirtualDesktopManager::self();
    for (uint i = 0; i < vds->maximum(); ++i) {
        auto handler = [this, i]() {
            const QList<VirtualDesktop *> desktops = VirtualDesktopManager::self()->desktops();
            if (i < uint(desktops.count())) {
                slotWindowToDesktop(desktops[i]);
            }
        };
        initShortcut(QStringLiteral("Window to Desktop %1").arg(i + 1), i18n("Window to Desktop %1", i + 1), 0, handler, true);
    }
    initShortcut("Window to Next Desktop", i18n("Window to Next Desktop"), 0, &Workspace::slotWindowToNextDesktop, true);
    initShortcut("Window to Previous Desktop", i18n("Window to Previous Desktop"), 0, &Workspace::slotWindowToPreviousDesktop, true);
    initShortcut("Window One Desktop to the Right", i18n("Window One Desktop to the Right"),
                 Qt::META | Qt::CTRL | Qt::SHIFT | Qt::Key_Right, &Workspace::slotWindowToDesktopRight, true);
    initShortcut("Window One Desktop to the Left", i18n("Window One Desktop to the Left"),
                 Qt::META | Qt::CTRL | Qt::SHIFT | Qt::Key_Left, &Workspace::slotWindowToDesktopLeft, true);
    initShortcut("Window One Desktop Up", i18n("Window One Desktop Up"),
                 Qt::META | Qt::CTRL | Qt::SHIFT | Qt::Key_Up, &Workspace::slotWindowToDesktopUp, true);
    initShortcut("Window One Desktop Down", i18n("Window One Desktop Down"),
                 Qt::META | Qt::CTRL | Qt::SHIFT | Qt::Key_Down, &Workspace::slotWindowToDesktopDown, true);

    for (int i = 0; i < 8; ++i) {
        initShortcut(QStringLiteral("Window to Screen %1").arg(i), i18n("Move Window to Screen %1", i), 0, [this, i]() {
            const auto order = outputOrder();
            if (i < order.size()) {
                slotWindowToScreen(order[i]);
            }
        }, true);
    }
    initShortcut("Window to Next Screen", i18n("Move Window to Next Screen"),
                 Qt::META | Qt::SHIFT | Qt::Key_Right, &Workspace::slotWindowToNextScreen, true);
    initShortcut("Window to Previous Screen", i18n("Move Window to Previous Screen"),
                 Qt::META | Qt::SHIFT | Qt::Key_Left, &Workspace::slotWindowToPrevScreen, true);
    initShortcut("Window One Screen to the Right", i18n("Move Window One Screen to the Right"),
                 0, &Workspace::slotWindowToRightScreen, true);
    initShortcut("Window One Screen to the Left", i18n("Move Window One Screen to the Left"),
                 0, &Workspace::slotWindowToLeftScreen, true);
    initShortcut("Window One Screen Up", i18n("Move Window One Screen Up"),
                 0, &Workspace::slotWindowToAboveScreen, true);
    initShortcut("Window One Screen Down", i18n("Move Window One Screen Down"),
                 0, &Workspace::slotWindowToBelowScreen, true);

    for (int i = 0; i < 8; ++i) {
        initShortcut(QStringLiteral("Switch to Screen %1").arg(i), i18n("Switch to Screen %1", i), 0, [this, i]() {
            const auto order = outputOrder();
            if (i < order.size()) {
                slotSwitchToScreen(order[i]);
            }
        }, true);
    }
    initShortcut("Switch to Next Screen", i18n("Switch to Next Screen"), 0, &Workspace::slotSwitchToNextScreen, true);
    initShortcut("Switch to Previous Screen", i18n("Switch to Previous Screen"), 0, &Workspace::slotSwitchToPrevScreen, true);
    initShortcut("Switch to Screen to the Right", i18n("Switch to Screen to the Right"),
                 0, &Workspace::slotSwitchToRightScreen, true);
    initShortcut("Switch to Screen to the Left", i18n("Switch to Screen to the Left"),
                 0, &Workspace::slotSwitchToLeftScreen, true);
    initShortcut("Switch to Screen Above", i18n("Switch to Screen Above"),
                 0, &Workspace::slotSwitchToAboveScreen, true);
    initShortcut("Switch to Screen Below", i18n("Switch to Screen Below"),
                 0, &Workspace::slotSwitchToBelowScreen, true);

    initShortcut("Show Desktop", i18n("Peek at Desktop"),
                 Qt::META | Qt::Key_D, &Workspace::slotToggleShowDesktop, false);

    initShortcut("Kill Window", i18n("Kill Window"), Qt::META | Qt::CTRL | Qt::Key_Escape, &Workspace::slotKillWindow, true);

    initShortcut(QStringLiteral("MoveMouseToFocus"), i18n("Move Mouse to Focus"), QKeySequence(Qt::META | Qt::Key_F5), &Workspace::slotMouseToFocus, false);
    initShortcut(QStringLiteral("MoveMouseToCenter"), i18n("Move Mouse to Center"), QKeySequence(Qt::META | Qt::Key_F6), &Workspace::slotMouseToCenter, false);

#if KWIN_BUILD_TABBOX
    m_tabbox->initShortcuts();
#endif
    vds->initShortcuts();
}


void Workspace::windowShortcutUpdated(Window *window)
{
    QString key = QStringLiteral("_k_session:%1").arg(window->internalId().toString());
    QAction *action = findChild<QAction *>(key);
    if (!window->shortcut().isEmpty()) {
        if (action == nullptr) { // new shortcut
            action = new QAction(this);
            connect(window, &Window::closed, action, [action]() {
                KGlobalAccel::self()->removeAllShortcuts(action);
                delete action;
            });

            action->setProperty("componentName", QStringLiteral("kwin"));
            action->setObjectName(key);
            action->setText(i18n("Activate Window (%1)", window->caption()));
            connect(action, &QAction::triggered, window, std::bind(&Workspace::activateWindow, this, window, true));
        }

        // no autoloading, since it's configured explicitly here and is not meant to be reused
        // (the key is the window id anyway, which is kind of random)
        KGlobalAccel::self()->setShortcut(action, QList<QKeySequence>() << window->shortcut(),
                                          KGlobalAccel::NoAutoloading);
        action->setEnabled(true);
    } else {
        KGlobalAccel::self()->removeAllShortcuts(action);
        delete action;
    }
}

void Workspace::performWindowOperation(Window *window, Options::WindowOperation op)
{
    if (!window) {
        return;
    }
    if (op == Options::MoveOp || op == Options::UnrestrictedMoveOp) {
        input()->pointer()->warp(window->frameGeometry().center());
    }
    if (op == Options::ResizeOp || op == Options::UnrestrictedResizeOp) {
        input()->pointer()->warp(window->frameGeometry().bottomRight());
    }
    switch (op) {
    case Options::MoveOp:
        window->performMousePressCommand(Options::MouseMove, Cursors::self()->mouse()->pos());
        break;
    case Options::UnrestrictedMoveOp:
        window->performMousePressCommand(Options::MouseUnrestrictedMove, Cursors::self()->mouse()->pos());
        break;
    case Options::ResizeOp:
        window->performMousePressCommand(Options::MouseResize, Cursors::self()->mouse()->pos());
        break;
    case Options::UnrestrictedResizeOp:
        window->performMousePressCommand(Options::MouseUnrestrictedResize, Cursors::self()->mouse()->pos());
        break;
    case Options::CloseOp:
        QMetaObject::invokeMethod(window, &Window::closeWindow, Qt::QueuedConnection);
        break;
    case Options::MaximizeOp:
        window->maximize(window->maximizeMode() == MaximizeFull
                             ? MaximizeRestore
                             : MaximizeFull);
        raiseWindow(window);
        requestFocus(window);
        break;
    case Options::HMaximizeOp:
        window->maximize(window->maximizeMode() ^ MaximizeHorizontal);
        raiseWindow(window);
        requestFocus(window);
        break;
    case Options::VMaximizeOp:
        window->maximize(window->maximizeMode() ^ MaximizeVertical);
        raiseWindow(window);
        requestFocus(window);
        break;
    case Options::UntileOrRestoreOp:
        // Un-fullscreen takes priority
        if (window->isFullScreen()) {
            window->setFullScreen(false);
        }
        // Un-tile if tiled
        else if (window->requestedQuickTileMode() != QuickTileMode(QuickTileFlag::None)) {
            window->setQuickTileModeAtCurrentPosition(QuickTileFlag::None);
        }
        // Un-maximize if maximized
        else if (window->requestedMaximizeMode() != MaximizeRestore) {
            window->maximize(MaximizeRestore);
        }
        raiseWindow(window);
        requestFocus(window);
        break;
    case Options::MinimizeOp:
        window->setMinimized(true);
        break;
    case Options::OnAllDesktopsOp:
        window->setOnAllDesktops(!window->isOnAllDesktops());
        break;
    case Options::FullScreenOp:
        window->setFullScreen(!window->isFullScreen());
        break;
    case Options::NoBorderOp:
        if (window->userCanSetNoBorder()) {
            window->setNoBorder(!window->noBorder());
        }
        break;
    case Options::ExcludeFromCaptureOp:
        window->setExcludeFromCapture(!window->excludeFromCapture());
        break;
    case Options::KeepAboveOp: {
        StackingUpdatesBlocker blocker(this);
        bool was = window->keepAbove();
        window->setKeepAbove(!window->keepAbove());
        if (was && !window->keepAbove()) {
            raiseWindow(window);
        }
        break;
    }
    case Options::KeepBelowOp: {
        StackingUpdatesBlocker blocker(this);
        bool was = window->keepBelow();
        window->setKeepBelow(!window->keepBelow());
        if (was && !window->keepBelow()) {
            lowerWindow(window);
        }
        break;
    }
    case Options::WindowRulesOp:
        m_rulebook->edit(window, false);
        break;
    case Options::ApplicationRulesOp:
        m_rulebook->edit(window, true);
        break;
    case Options::SetupWindowShortcutOp:
        break;
    case Options::LowerOp:
        lowerWindow(window);
        break;
    case Options::NoOp:
        break;
    }
}

void Workspace::slotActivateAttentionWindow()
{
    if (attention_chain.count() > 0) {
        activateWindow(attention_chain.first());
    }
}

#define USABLE_ACTIVE_WINDOW (m_activeWindow && !(m_activeWindow->isDesktop() || m_activeWindow->isDock()))

void Workspace::slotWindowToDesktop(VirtualDesktop *desktop)
{
    if (USABLE_ACTIVE_WINDOW) {
        sendWindowToDesktops(m_activeWindow, {desktop}, true);
    }
}

void Workspace::slotSwitchToScreen(LogicalOutput *output)
{
    switchToOutput(output);
}

void Workspace::slotSwitchToLeftScreen()
{
    switchToOutput(findOutput(activeOutput(), Direction::DirectionWest, true));
}

void Workspace::slotSwitchToRightScreen()
{
    switchToOutput(findOutput(activeOutput(), Direction::DirectionEast, true));
}

void Workspace::slotSwitchToAboveScreen()
{
    switchToOutput(findOutput(activeOutput(), Direction::DirectionNorth, true));
}

void Workspace::slotSwitchToBelowScreen()
{
    switchToOutput(findOutput(activeOutput(), Direction::DirectionSouth, true));
}

void Workspace::slotSwitchToPrevScreen()
{
    switchToOutput(findOutput(activeOutput(), Direction::DirectionPrev, true));
}

void Workspace::slotSwitchToNextScreen()
{
    switchToOutput(findOutput(activeOutput(), Direction::DirectionNext, true));
}

void Workspace::slotWindowToScreen(LogicalOutput *output)
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(output);
    }
}

void Workspace::slotWindowToLeftScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(findOutput(m_activeWindow->output(), Direction::DirectionWest, true));
    }
}

void Workspace::slotWindowToRightScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(findOutput(m_activeWindow->output(), Direction::DirectionEast, true));
    }
}

void Workspace::slotWindowToAboveScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(findOutput(m_activeWindow->output(), Direction::DirectionNorth, true));
    }
}

void Workspace::slotWindowToBelowScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(findOutput(m_activeWindow->output(), Direction::DirectionSouth, true));
    }
}

void Workspace::slotWindowToPrevScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(findOutput(m_activeWindow->output(), Direction::DirectionPrev, true));
    }
}

void Workspace::slotWindowToNextScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->sendToOutput(findOutput(m_activeWindow->output(), Direction::DirectionNext, true));
    }
}

/**
 * Maximizes the active window.
 */
void Workspace::slotWindowMaximize()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::MaximizeOp);
    }
}

/**
 * Maximizes the active window vertically.
 */
void Workspace::slotWindowMaximizeVertical()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::VMaximizeOp);
    }
}

/**
 * Maximizes the active window horiozontally.
 */
void Workspace::slotWindowMaximizeHorizontal()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::HMaximizeOp);
    }
}

/**
 * Restores the active window (un-fullscreen, un-tile, or un-maximize).
 */
void Workspace::slotWindowRestore()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::UntileOrRestoreOp);
    }
}

/**
 * Minimizes the active window.
 */
void Workspace::slotWindowMinimize()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::MinimizeOp);
    }
}

/**
 * Raises the active window.
 */
void Workspace::slotWindowRaise()
{
    if (USABLE_ACTIVE_WINDOW) {
        raiseWindow(m_activeWindow);
    }
}

/**
 * Lowers the active window.
 */
void Workspace::slotWindowLower()
{
    if (USABLE_ACTIVE_WINDOW) {
        lowerWindow(m_activeWindow);
        // As this most likely makes the window no longer visible change the
        // keyboard focus to the next available window.
        // activateNextWindow( c ); // Doesn't work when we lower a child window
        if (m_activeWindow->isActive() && options->focusPolicyIsReasonable()) {
            if (options->isNextFocusPrefersMouse()) {
                Window *next = windowUnderMouse(m_activeWindow->output());
                if (next && next != m_activeWindow) {
                    requestFocus(next, false);
                }
            } else {
                activateWindow(topWindowOnDesktop(VirtualDesktopManager::self()->currentDesktop(m_activeWindow->output())));
            }
        }
    }
}

/**
 * Does a toggle-raise-and-lower on the active window.
 */
void Workspace::slotWindowRaiseOrLower()
{
    if (USABLE_ACTIVE_WINDOW) {
        raiseOrLowerWindow(m_activeWindow);
    }
}

void Workspace::slotWindowOnAllDesktops()
{
    if (USABLE_ACTIVE_WINDOW) {
        m_activeWindow->setOnAllDesktops(!m_activeWindow->isOnAllDesktops());
    }
}

void Workspace::slotWindowFullScreen()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::FullScreenOp);
    }
}

void Workspace::slotWindowNoBorder()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::NoBorderOp);
    }
}

void Workspace::slotWindowExcludeFromCapture()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::ExcludeFromCaptureOp);
    }
}

void Workspace::slotWindowAbove()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::KeepAboveOp);
    }
}

void Workspace::slotWindowBelow()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::KeepBelowOp);
    }
}

/**
 * Toggles show desktop.
 */
void Workspace::slotToggleShowDesktop()
{
    setShowingDesktop(!showingDesktop());
}

void windowToDesktop(Window *window, VirtualDesktopManager::Direction direction)
{
    if (window->isDesktop() || window->isDock()) {
        return;
    }

    VirtualDesktopManager *vds = VirtualDesktopManager::self();
    Workspace *ws = Workspace::self();
    // TODO: why is options->isRollOverDesktops() not honored?
    const auto desktop = vds->inDirection(vds->currentDesktop(window->output()), direction, true);
    if (ws->moveResizeWindow()) {
        if (ws->moveResizeWindow() == window) {
            vds->setCurrent(desktop, window->output());
        }
    } else {
        ws->setMoveResizeWindow(window);
        vds->setCurrent(desktop, window->output());
        ws->setMoveResizeWindow(nullptr);
    }
}

/**
 * Moves the active window to the next desktop.
 */
void Workspace::slotWindowToNextDesktop()
{
    if (USABLE_ACTIVE_WINDOW) {
        windowToNextDesktop(m_activeWindow);
    }
}

void Workspace::windowToNextDesktop(Window *window)
{
    windowToDesktop(window, VirtualDesktopManager::Direction::Next);
}

/**
 * Moves the active window to the previous desktop.
 */
void Workspace::slotWindowToPreviousDesktop()
{
    if (USABLE_ACTIVE_WINDOW) {
        windowToPreviousDesktop(m_activeWindow);
    }
}

void Workspace::windowToPreviousDesktop(Window *window)
{
    windowToDesktop(window, VirtualDesktopManager::Direction::Previous);
}

void activeWindowToDesktop(VirtualDesktopManager::Direction direction)
{
    VirtualDesktopManager *vds = VirtualDesktopManager::self();
    Workspace *ws = Workspace::self();
    VirtualDesktop *current = vds->currentDesktop(ws->activeWindow()->output());
    VirtualDesktop *newCurrent = VirtualDesktopManager::self()->inDirection(current, direction, options->isRollOverDesktops());
    if (newCurrent == current) {
        return;
    }
    if (ws->moveResizeWindow()) {
        if (ws->moveResizeWindow() == ws->activeWindow()) {
            vds->setCurrent(newCurrent, ws->activeWindow()->output());
        }
    } else {
        ws->setMoveResizeWindow(ws->activeWindow());
        vds->setCurrent(newCurrent, ws->activeWindow()->output());
        ws->setMoveResizeWindow(nullptr);
    }
}

void Workspace::slotWindowToDesktopRight()
{
    if (USABLE_ACTIVE_WINDOW) {
        activeWindowToDesktop(VirtualDesktopManager::Direction::Right);
    }
}

void Workspace::slotWindowToDesktopLeft()
{
    if (USABLE_ACTIVE_WINDOW) {
        activeWindowToDesktop(VirtualDesktopManager::Direction::Left);
    }
}

void Workspace::slotWindowToDesktopUp()
{
    if (USABLE_ACTIVE_WINDOW) {
        activeWindowToDesktop(VirtualDesktopManager::Direction::Up);
    }
}

void Workspace::slotWindowToDesktopDown()
{
    if (USABLE_ACTIVE_WINDOW) {
        activeWindowToDesktop(VirtualDesktopManager::Direction::Down);
    }
}

/**
 * Kill Window feature, similar to xkill.
 */
void Workspace::slotKillWindow()
{
    if (!m_windowKiller) {
        m_windowKiller = std::make_unique<KillWindow>();
    }
    m_windowKiller->start();
}

/**
 * Switches to the nearest window in given direction.
 */
void Workspace::switchWindow(Direction direction)
{
    if (!m_activeWindow) {
        return;
    }
    Window *window = m_activeWindow;
    VirtualDesktop *desktop = VirtualDesktopManager::self()->currentDesktop(m_activeWindow->output());

    // Center of the active window
    QPoint curPos(window->x() + window->width() / 2, window->y() + window->height() / 2);

    if (!switchWindow(window, direction, curPos, desktop)) {
        auto opposite = [&] {
            switch (direction) {
            case DirectionNorth:
                return QPoint(curPos.x(), geometry().height());
            case DirectionSouth:
                return QPoint(curPos.x(), 0);
            case DirectionEast:
                return QPoint(0, curPos.y());
            case DirectionWest:
                return QPoint(geometry().width(), curPos.y());
            default:
                Q_UNREACHABLE();
            }
        };

        switchWindow(window, direction, opposite(), desktop);
    }
}

bool Workspace::switchWindow(Window *window, Direction direction, QPoint curPos, VirtualDesktop *desktop)
{
    Window *switchTo = nullptr;
    int bestScore = 0;

    QList<Window *> clist = stackingOrder();
    for (auto i = clist.rbegin(); i != clist.rend(); ++i) {
        auto other = *i;
        if (!other->isClient()) {
            continue;
        }
        if (other->wantsTabFocus() && *i != window && other->isOnDesktop(desktop) && !other->isMinimized() && (*i)->isOnCurrentActivity()) {
            // Center of the other window
            const QPoint otherCenter(other->x() + other->width() / 2, other->y() + other->height() / 2);

            int distance;
            int offset;
            switch (direction) {
            case DirectionNorth:
                distance = curPos.y() - otherCenter.y();
                offset = std::abs(otherCenter.x() - curPos.x());
                break;
            case DirectionEast:
                distance = otherCenter.x() - curPos.x();
                offset = std::abs(otherCenter.y() - curPos.y());
                break;
            case DirectionSouth:
                distance = otherCenter.y() - curPos.y();
                offset = std::abs(otherCenter.x() - curPos.x());
                break;
            case DirectionWest:
                distance = curPos.x() - otherCenter.x();
                offset = std::abs(otherCenter.y() - curPos.y());
                break;
            default:
                distance = -1;
                offset = -1;
            }

            if (distance > 0) {
                // Inverse score
                int score = distance + offset + ((offset * offset) / distance);
                if (score < bestScore || !switchTo) {
                    switchTo = other;
                    bestScore = score;
                }
            }
        }
    }
    if (switchTo) {
        activateWindow(switchTo);
    }

    return switchTo;
}

/**
 * Shows the window operations popup menu for the active window.
 */
void Workspace::slotWindowOperations()
{
    if (!m_activeWindow) {
        return;
    }
    const QPoint pos(m_activeWindow->frameGeometry().left() + m_activeWindow->frameMargins().left(),
                     m_activeWindow->frameGeometry().top() + m_activeWindow->frameMargins().top());
    showWindowMenu(Rect(pos, pos), m_activeWindow);
}

void Workspace::showWindowMenu(const Rect &pos, Window *window)
{
    if (!window) {
        return;
    }
    if (auto *ipc = findChild<KaskadIpc *>()) {
        Q_EMIT ipc->windowMenuRequested(window->internalId().toString(), pos.x(), pos.y());
    }
}

void Workspace::showApplicationMenu(const Rect &pos, Window *window, int actionId)
{
    Workspace::self()->applicationMenu()->showApplicationMenu(window->pos().toPoint() + pos.bottomLeft(), window, actionId);
}

/**
 * Closes the active window.
 */
void Workspace::slotWindowClose()
{
    // TODO: why?
    //     if ( tab_box->isVisible())
    //         return;
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::CloseOp);
    }
}

/**
 * Starts keyboard move mode for the active window.
 */
void Workspace::slotWindowMove()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::UnrestrictedMoveOp);
    }
}

/**
 * Starts keyboard resize mode for the active window.
 */
void Workspace::slotWindowResize()
{
    if (USABLE_ACTIVE_WINDOW) {
        performWindowOperation(m_activeWindow, Options::UnrestrictedResizeOp);
    }
}

void Workspace::slotMouseToFocus()
{
    if (USABLE_ACTIVE_WINDOW) {
        input()->pointer()->warp(m_activeWindow->frameGeometry().center());
    }
}

void Workspace::slotMouseToCenter()
{
    input()->pointer()->warp(m_activeOutput->geometryF().center());
}

#undef USABLE_ACTIVE_WINDOW

void Window::setShortcut(const QString &_cut)
{
    QString cut = rules()->checkShortcut(_cut);
    auto updateShortcut = [this](const QKeySequence &cut = QKeySequence()) {
        if (_shortcut == cut) {
            return;
        }
        _shortcut = cut;
        setShortcutInternal();
    };
    if (cut.isEmpty()) {
        updateShortcut();
        return;
    }
    if (cut == shortcut().toString()) {
        return; // no change
    }
    // Format:
    // base+(abcdef)<space>base+(abcdef)
    // E.g. Alt+Ctrl+(ABCDEF);Meta+X,Meta+(ABCDEF)
    if (!cut.contains(QLatin1Char('(')) && !cut.contains(QLatin1Char(')')) && !cut.contains(QLatin1StringView(" - "))) {
        if (workspace()->shortcutAvailable(cut, this)) {
            updateShortcut(QKeySequence(cut));
        } else {
            updateShortcut();
        }
        return;
    }
    static const QRegularExpression reg(QStringLiteral("(.*\\+)\\((.*)\\)"));
    QList<QKeySequence> keys;
    const QStringList groups = cut.split(QStringLiteral(" - "));
    for (auto it = groups.begin(); it != groups.end(); ++it) {
        const QRegularExpressionMatch match = reg.match(*it);
        if (match.hasMatch()) {
            const QString base = match.captured(1);
            const QString list = match.captured(2);
            for (int i = 0; i < list.length(); ++i) {
                QKeySequence c(base + list[i]);
                if (!c.isEmpty()) {
                    keys.append(c);
                }
            }
        } else {
            // regexp doesn't match, so it should be a normal shortcut
            QKeySequence c(*it);
            if (!c.isEmpty()) {
                keys.append(c);
            }
        }
    }
    for (auto it = keys.constBegin(); it != keys.cend(); ++it) {
        if (_shortcut == *it) { // current one is in the list
            return;
        }
    }
    for (auto it = keys.cbegin(); it != keys.cend(); ++it) {
        if (workspace()->shortcutAvailable(*it, this)) {
            updateShortcut(*it);
            return;
        }
    }
    updateShortcut();
}

void Window::setShortcutInternal()
{
    updateCaption();
    workspace()->windowShortcutUpdated(this);
}

bool Workspace::shortcutAvailable(const QKeySequence &cut, Window *ignore) const
{
    if (ignore && cut == ignore->shortcut()) {
        return true;
    }

    // Check if the shortcut is already registered
    const QList<KGlobalShortcutInfo> registeredShortcuts = KGlobalAccel::globalShortcutsByKey(cut);
    for (const auto &shortcut : registeredShortcuts) {
        // Only return "not available" if is not a window activation shortcut, as it may be no longer valid
        if (!shortcut.uniqueName().startsWith(QStringLiteral("_k_session:"))) {
            return false;
        }
    }
    // Check now conflicts with activation shortcuts for current windows
    for (const auto window : std::as_const(m_windows)) {
        if (window != ignore && window->shortcut() == cut) {
            return false;
        }
    }
    return true;
}

} // namespace
