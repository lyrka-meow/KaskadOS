/*
    SPDX-FileCopyrightText: 2026 KaskadOS contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QColor>
#include <QImage>

namespace KWin::CursorColor
{
QColor contrastingOutline(const QColor &accent);
quint32 recolorPixel(quint32 pixel, const QColor &accent, const QColor &outline);
void recolorImage(QImage &image, const QColor &accent);
}
