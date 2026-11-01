/*
    SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "decorationbridge.h"

#include "decoratedwindow.h"
#include "kaskaddecoration.h"
#include "main.h"
#include "settings.h"
#include "wayland/server_decoration.h"
#include "wayland_server.h"
#include "window.h"
#include "workspace.h"

#include <KConfigGroup>
#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationSettings>

#include <QMetaProperty>

namespace KWin::Decoration
{

namespace
{
constexpr auto s_configGroup = "KaskadDecoration";

QColor validColor(const QVariantMap &palette, const QString &key, const QColor &fallback)
{
    const QColor candidate(palette.value(key).toString());
    return candidate.isValid() ? candidate : fallback;
}

QString settingsProperty(const QVariant &variant)
{
    if (QLatin1StringView(variant.typeName()) == QLatin1StringView("KDecoration3::BorderSize")) {
        return QString::number(variant.toInt());
    }
    if (QLatin1StringView(variant.typeName()) == QLatin1StringView("QList<KDecoration3::DecorationButtonType>")) {
        const auto buttons = variant.value<QList<KDecoration3::DecorationButtonType>>();
        QStringList values;
        for (const auto button : buttons) {
            values.append(QString::number(int(button)));
        }
        return values.join(QStringLiteral(", "));
    }
    return variant.toString();
}
}

DecorationBridge::DecorationBridge()
    : m_showToolTips(false)
    , m_noPlugin(false)
{
    readDecorationOptions();
    readPalette();
}

void DecorationBridge::readDecorationOptions()
{
    // Kaskad owns one built-in frame. Plugin and theme selection are
    // deliberately not read from user configuration.
    m_showToolTips = kwinApp()->config()->group(QStringLiteral("org.kde.kdecoration2"))
        .readEntry("ShowToolTips", true);
}

void DecorationBridge::readPalette()
{
    const KConfigGroup group(kwinApp()->config(), QString::fromLatin1(s_configGroup));
    m_surface = group.readEntry("Surface", m_surface);
    m_surfaceInactive = group.readEntry("SurfaceInactive", m_surfaceInactive);
    m_foreground = group.readEntry("Foreground", m_foreground);
    m_foregroundInactive = group.readEntry("ForegroundInactive", m_foregroundInactive);
    m_outline = group.readEntry("Outline", m_outline);
    m_accent = group.readEntry("Accent", m_accent);
    m_error = group.readEntry("Error", m_error);
    m_outlineEnabled = group.readEntry("OutlineEnabled", m_outlineEnabled);
}

bool DecorationBridge::hasPlugin()
{
    const DecorationBridge *bridge = workspace()->decorationBridge();
    return bridge && !bridge->m_noPlugin;
}

void DecorationBridge::init()
{
    m_settings = std::make_shared<KDecoration3::DecorationSettings>(this);
    waylandServer()->decorationManager()->setDefaultMode(ServerSideDecorationManagerInterface::Mode::Server);
}

std::unique_ptr<KDecoration3::DecoratedWindowPrivate> DecorationBridge::createClient(KDecoration3::DecoratedWindow *client,
                                                                                    KDecoration3::Decoration *decoration)
{
    return std::make_unique<DecoratedWindowImpl>(static_cast<Window *>(decoration->parent()), client, decoration);
}

std::unique_ptr<KDecoration3::DecorationSettingsPrivate> DecorationBridge::settings(KDecoration3::DecorationSettings *parent)
{
    return std::make_unique<SettingsImpl>(parent);
}

KDecoration3::Decoration *DecorationBridge::createDecoration(Window *window)
{
    if (m_noPlugin) {
        return nullptr;
    }

    const QVariantMap bridgeArgument{{QStringLiteral("bridge"), QVariant::fromValue(this)}};
    auto *decoration = new KaskadDecoration(window, QVariantList{bridgeArgument}, this);
    decoration->setSettings(m_settings);
    decoration->create();
    decoration->init();
    return decoration;
}

bool DecorationBridge::setPalette(const QVariantMap &palette)
{
    if (palette.isEmpty()) {
        return false;
    }

    const QColor surface = validColor(palette, QStringLiteral("surface"), m_surface);
    const QColor surfaceInactive = validColor(palette, QStringLiteral("surfaceInactive"), m_surfaceInactive);
    const QColor foreground = validColor(palette, QStringLiteral("foreground"), m_foreground);
    const QColor foregroundInactive = validColor(palette, QStringLiteral("foregroundInactive"), m_foregroundInactive);
    const QColor outline = validColor(palette, QStringLiteral("outline"), m_outline);
    const QColor accent = validColor(palette, QStringLiteral("accent"), m_accent);
    const QColor error = validColor(palette, QStringLiteral("error"), m_error);
    const bool outlineEnabled = palette.contains(QStringLiteral("outlineEnabled"))
        ? palette.value(QStringLiteral("outlineEnabled")).toBool()
        : m_outlineEnabled;

    if (surface == m_surface && surfaceInactive == m_surfaceInactive
        && foreground == m_foreground && foregroundInactive == m_foregroundInactive
        && outline == m_outline && accent == m_accent && error == m_error
        && outlineEnabled == m_outlineEnabled) {
        return true;
    }

    m_surface = surface;
    m_surfaceInactive = surfaceInactive;
    m_foreground = foreground;
    m_foregroundInactive = foregroundInactive;
    m_outline = outline;
    m_accent = accent;
    m_error = error;
    m_outlineEnabled = outlineEnabled;

    KConfigGroup group(kwinApp()->config(), QString::fromLatin1(s_configGroup));
    group.writeEntry("Surface", m_surface);
    group.writeEntry("SurfaceInactive", m_surfaceInactive);
    group.writeEntry("Foreground", m_foreground);
    group.writeEntry("ForegroundInactive", m_foregroundInactive);
    group.writeEntry("Outline", m_outline);
    group.writeEntry("Accent", m_accent);
    group.writeEntry("Error", m_error);
    group.writeEntry("OutlineEnabled", m_outlineEnabled);
    group.sync();

    Q_EMIT paletteChanged();
    return true;
}

QVariantMap DecorationBridge::palette() const
{
    return {
        {QStringLiteral("surface"), m_surface.name(QColor::HexArgb)},
        {QStringLiteral("surfaceInactive"), m_surfaceInactive.name(QColor::HexArgb)},
        {QStringLiteral("foreground"), m_foreground.name(QColor::HexArgb)},
        {QStringLiteral("foregroundInactive"), m_foregroundInactive.name(QColor::HexArgb)},
        {QStringLiteral("outline"), m_outline.name(QColor::HexArgb)},
        {QStringLiteral("accent"), m_accent.name(QColor::HexArgb)},
        {QStringLiteral("error"), m_error.name(QColor::HexArgb)},
        {QStringLiteral("outlineEnabled"), m_outlineEnabled},
    };
}

QColor DecorationBridge::surfaceColor(bool active) const
{
    return active ? m_surface : m_surfaceInactive;
}

QColor DecorationBridge::foregroundColor(bool active) const
{
    return active ? m_foreground : m_foregroundInactive;
}

QColor DecorationBridge::outlineColor(bool active) const
{
    QColor color = active ? m_accent : m_outline;
    color.setAlphaF(active ? 0.48 : 0.28);
    return color;
}

bool DecorationBridge::outlineEnabled() const
{
    return m_outlineEnabled;
}

QColor DecorationBridge::accentColor() const
{
    return m_accent;
}

QColor DecorationBridge::errorColor() const
{
    return m_error;
}

void DecorationBridge::reconfigure()
{
    readDecorationOptions();
    readPalette();
    Q_EMIT paletteChanged();
}

QString DecorationBridge::supportInformation() const
{
    QString result = QStringLiteral("Decoration: built-in Kaskad Material frame\n");
    result += QStringLiteral("External decoration plugins: disabled\n");
    result += QStringLiteral("Surface: %1\nAccent: %2\nOutline enabled: %3\n")
                  .arg(m_surface.name(), m_accent.name(), m_outlineEnabled ? QStringLiteral("yes") : QStringLiteral("no"));
    if (m_settings) {
        const QMetaObject *options = m_settings->metaObject();
        for (int i = 0; i < options->propertyCount(); ++i) {
            const QMetaProperty property = options->property(i);
            if (QLatin1StringView(property.name()) != QLatin1StringView("objectName")) {
                result += QStringLiteral("%1: %2\n").arg(property.name(), settingsProperty(m_settings->property(property.name())));
            }
        }
    }
    return result;
}

} // namespace KWin::Decoration

#include "moc_decorationbridge.cpp"
