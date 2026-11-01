/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include "kwin_export.h"
#include <KDecoration3/Private/DecorationBridge>
#include <QColor>
#include <QObject>
#include <QVariantMap>

namespace KDecoration3
{

class DecorationSettings;

}

namespace KWin
{

class Window;

namespace Decoration
{

class KWIN_EXPORT DecorationBridge : public KDecoration3::DecorationBridge
{
    Q_OBJECT

public:
    explicit DecorationBridge();

    static bool hasPlugin();

    void init();
    KDecoration3::Decoration *createDecoration(Window *window);

    bool setPalette(const QVariantMap &palette);
    QVariantMap palette() const;
    QColor surfaceColor(bool active) const;
    QColor foregroundColor(bool active) const;
    QColor outlineColor(bool active) const;
    bool outlineEnabled() const;
    QColor accentColor() const;
    QColor errorColor() const;

    std::unique_ptr<KDecoration3::DecoratedWindowPrivate> createClient(KDecoration3::DecoratedWindow *client, KDecoration3::Decoration *decoration) override;
    std::unique_ptr<KDecoration3::DecorationSettingsPrivate> settings(KDecoration3::DecorationSettings *parent) override;

    QString recommendedBorderSize() const
    {
        return QStringLiteral("Normal");
    }

    bool showToolTips() const
    {
        return m_showToolTips;
    }

    void reconfigure();

    const std::shared_ptr<KDecoration3::DecorationSettings> &settings() const
    {
        return m_settings;
    }

    QString supportInformation() const;

Q_SIGNALS:
    void paletteChanged();

private:
    void readDecorationOptions();
    void readPalette();
    bool m_showToolTips;
    std::shared_ptr<KDecoration3::DecorationSettings> m_settings;
    bool m_noPlugin;
    QColor m_surface = QColor(QStringLiteral("#1E201C"));
    QColor m_surfaceInactive = QColor(QStringLiteral("#1A1C19"));
    QColor m_foreground = QColor(QStringLiteral("#E2E3DD"));
    QColor m_foregroundInactive = QColor(QStringLiteral("#C2C8BD"));
    QColor m_outline = QColor(QStringLiteral("#8C9388"));
    QColor m_accent = QColor(QStringLiteral("#9FE0B4"));
    QColor m_error = QColor(QStringLiteral("#FFB4AB"));
    bool m_outlineEnabled = false;
};

} // Decoration
} // KWin
