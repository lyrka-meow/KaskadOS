/*
    SPDX-FileCopyrightText: 2020 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "effect/globals.h"

#include <QObject>

namespace KWin
{

class CompositorService;

/**
 * Owns the fixed set of compositor subsystems built into Kaskad.
 */
class KWIN_EXPORT CoreServiceManager : public QObject
{
    Q_OBJECT

public:
    CoreServiceManager();
    ~CoreServiceManager() override;

    QStringList activeServices() const;

private:
    std::map<QString, std::unique_ptr<CompositorService>> m_services;
};

} // namespace KWin
