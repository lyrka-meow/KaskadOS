/*
 * SPDX-FileCopyrightText: 2016 Red Hat Inc
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 *
 * SPDX-FileCopyrightText: 2016 Jan Grulich <jgrulich@redhat.com>
 */

#include "desktopportal.h"

#include <QStringList>
#include "desktopportal_debug.h"

#include "access.h"
#include "account.h"
#include "appchooser.h"
#include "background.h"
#include "clipboard.h"
#include "dynamiclauncher.h"
#include "email.h"
#include "filechooser.h"
#include "globalshortcuts.h"
#include "inhibit.h"
#include "notification.h"
#include "inputcapture.h"
#include "print.h"
#include "remotedesktop.h"
#include "screencast.h"
#include "screenshot.h"
#include "settings.h"
#include "usb.h"
#include "wallpaper.h"
#include "waylandintegration.h"

#include <KWindowSystem>

DesktopPortal::DesktopPortal(QObject *parent)
    : QObject(parent)
    , m_access(new AccessPortal(this))
    , m_account(new AccountPortal(this))
    , m_appChooser(new AppChooserPortal(this))
    , m_email(new EmailPortal(this))
    , m_fileChooser(new FileChooserPortal(this))
    , m_inhibit(new InhibitPortal(this))
    , m_print(new PrintPortal(this))
    , m_settings(new SettingsPortal(this))
    , m_dynamicLauncher(new DynamicLauncherPortal(this))
    , m_notification(new NotificationPortal(this))
{
    const QStringList desktops = qEnvironmentVariable("XDG_CURRENT_DESKTOP").split(u':', Qt::SkipEmptyParts);
    const bool isKde = desktops.contains(QStringLiteral("KDE"), Qt::CaseInsensitive);
    const bool isKaskad = desktops.contains(QStringLiteral("KaskadDesktop"), Qt::CaseInsensitive);
    if (isKde || isKaskad) {
        new GlobalShortcutsPortal(this);

        if (!KWindowSystem::isPlatformX11()) {
            m_background = new BackgroundPortal(this, this);
        }
        m_screenCast = new ScreenCastPortal(this);
        m_remoteDesktop = new RemoteDesktopPortal(this);
        m_screenshot = new ScreenshotPortal(this);
        new InputCapturePortal(this);
        new ClipboardPortal(this);
        new WallpaperPortal(this);
        WaylandIntegration::init();
    }
    new UsbPortal(this);
}

#include "moc_desktopportal.cpp"
