/*
    SPDX-FileCopyrightText: 2020 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "coreservicemanager.h"
#include "compositorservice.h"
#include "config-kwin.h"
#if !KASKAD_INSTALLER_MINIMAL
#include "plugins/nightlight/nightlightmanager.h"
#include "plugins/screencast/screencastmanager.h"
#include "plugins/screenshot/screenshot.h"
#endif

namespace KWin
{

CoreServiceManager::CoreServiceManager()
{
#if !KASKAD_INSTALLER_MINIMAL
    m_services.emplace(QStringLiteral("nightlight"), std::make_unique<NightLightManager>());
    m_services.emplace(QStringLiteral("screencast"), std::make_unique<ScreencastManager>());
    m_services.emplace(QStringLiteral("screenshot"), std::make_unique<ScreenShotManager>());
#endif
}

CoreServiceManager::~CoreServiceManager() = default;

QStringList CoreServiceManager::activeServices() const
{
    QStringList ret;
    ret.reserve(m_services.size());
    for (const auto &[key, _] : m_services) {
        ret.push_back(key);
    }
    return ret;
}

} // namespace KWin

#include "moc_coreservicemanager.cpp"
