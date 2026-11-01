/*
    SPDX-FileCopyrightText: 2026 KaskadOS contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "utils/cursorcolor.h"

#include <algorithm>

namespace KWin::CursorColor
{

QColor contrastingOutline(const QColor &accent)
{
    const qreal luminance = 0.2126 * accent.redF() + 0.7152 * accent.greenF() + 0.0722 * accent.blueF();
    return luminance > 0.46 ? QColor(QStringLiteral("#101713")) : QColor(QStringLiteral("#f4fff8"));
}

quint32 recolorPixel(quint32 pixel, const QColor &accent, const QColor &outline)
{
    const int alpha = (pixel >> 24) & 0xff;
    if (alpha == 0) {
        return pixel;
    }

    const int redPremultiplied = int((pixel >> 16) & 0xff);
    const int greenPremultiplied = int((pixel >> 8) & 0xff);
    const int bluePremultiplied = int(pixel & 0xff);
    const int red = std::min(255, (redPremultiplied * 255 + alpha / 2) / alpha);
    const int green = std::min(255, (greenPremultiplied * 255 + alpha / 2) / alpha);
    const int blue = std::min(255, (bluePremultiplied * 255 + alpha / 2) / alpha);
    const int high = std::max({red, green, blue});
    const int low = std::min({red, green, blue});

    // Bibata Ice uses neutral white for its body and neutral black for its
    // outline. Deliberately coloured status marks must remain untouched.
    if (high - low > 18) {
        return pixel;
    }

    const int luminance = (red * 54 + green * 183 + blue * 19) / 256;
    const QColor target = luminance >= 96 ? accent : outline;
    const quint32 pr = quint32((target.red() * alpha + 127) / 255);
    const quint32 pg = quint32((target.green() * alpha + 127) / 255);
    const quint32 pb = quint32((target.blue() * alpha + 127) / 255);
    return (quint32(alpha) << 24) | (pr << 16) | (pg << 8) | pb;
}

void recolorImage(QImage &image, const QColor &accent)
{
    if (!accent.isValid() || image.isNull()) {
        return;
    }
    if (image.format() != QImage::Format_ARGB32_Premultiplied) {
        image.convertTo(QImage::Format_ARGB32_Premultiplied);
    }
    const QColor outline = contrastingOutline(accent);
    for (int y = 0; y < image.height(); ++y) {
        auto *pixels = reinterpret_cast<quint32 *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            pixels[x] = recolorPixel(pixels[x], accent, outline);
        }
    }
}

}
