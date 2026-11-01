/*
    SPDX-FileCopyrightText: 2020 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <kwin_export.h>

#include <QObject>
#include <memory>

namespace KWin
{

/**
 * Base class for fixed compositor-owned services with QObject lifetime
 * management. Kaskad does not discover or load implementations at runtime.
 */
class KWIN_EXPORT CompositorService : public QObject
{
    Q_OBJECT

public:
    explicit CompositorService();
};

} // namespace KWin
