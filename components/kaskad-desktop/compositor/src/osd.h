/*
    SPDX-FileCopyrightText: 2016 Martin Graesslin <mgraesslin@kde.org>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL

*/

#pragma once

#include "kwin_export.h"

#include <QFlags>
#include <QString>

namespace KWin
{
namespace OSD
{

KWIN_EXPORT void show(const QString &message, const QString &iconName = QString());
KWIN_EXPORT void show(const QString &message, int timeout);
KWIN_EXPORT void show(const QString &message, const QString &iconName, int timeout);
enum class HideFlag {
    SkipCloseAnimation = 1,
};
Q_DECLARE_FLAGS(HideFlags, HideFlag)
KWIN_EXPORT void hide(HideFlags flags = HideFlags());

}
}
