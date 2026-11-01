/*
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kaskaddecoration.h"

#include "decorationbridge.h"

#include <KDecoration3/DecoratedWindow>

#include <QFontMetricsF>
#include <QFontDatabase>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QHoverEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>

#include <algorithm>

namespace KWin::Decoration
{

namespace
{
constexpr qreal s_titleHeight = 36.0;
constexpr qreal s_maximizedTitleHeight = 32.0;
constexpr qreal s_borderWidth = 1.0;
constexpr qreal s_resizeMargin = 6.0;
constexpr qreal s_cornerRadius = 12.0;
constexpr qreal s_controlWidth = 40.0;
constexpr qreal s_pinWidth = 36.0;

QString loadKaskadFont(const QString &relativeAsset, const QString &family)
{
    if (QFontDatabase::families().contains(family)) {
        return family;
    }

    const QDir applicationDir(QCoreApplication::applicationDirPath());
    const QDir sourceDir(QFileInfo(QString::fromUtf8(__FILE__)).absolutePath());
    const QStringList candidates{
        applicationDir.absoluteFilePath(QStringLiteral("../../../shell/KaskadShell/") + relativeAsset),
        applicationDir.absoluteFilePath(QStringLiteral("../../shell-source/") + relativeAsset),
        sourceDir.absoluteFilePath(QStringLiteral("../../../shell/KaskadShell/") + relativeAsset),
        QStringLiteral("/opt/kaskad-desktop/shell/KaskadShell/") + relativeAsset,
    };
    for (const QString &candidate : candidates) {
        if (!QFileInfo(candidate).isReadable()) {
            continue;
        }
        const int fontId = QFontDatabase::addApplicationFont(candidate);
        const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
        if (!families.isEmpty()) {
            return families.constFirst();
        }
    }
    return {};
}

QString materialSymbolsFamily()
{
    static const QString family = loadKaskadFont(
        QStringLiteral("kaskad-qml-common/KaskadCommon/assets/fonts/material-design-icons/variablefont/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"),
        QStringLiteral("Material Symbols Rounded"));
    return family;
}

QString interFamily()
{
    static const QString family = loadKaskadFont(
        QStringLiteral("kaskad-qml-common/KaskadCommon/assets/fonts/inter/InterVariable.ttf"),
        QStringLiteral("Inter Variable"));
    return family;
}

QColor withAlpha(QColor color, qreal alpha)
{
    color.setAlphaF(std::clamp(alpha, 0.0, 1.0));
    return color;
}
}

KaskadDecoration::KaskadDecoration(QObject *parent, const QVariantList &args, DecorationBridge *bridge)
    : KDecoration3::Decoration(parent, args)
    , m_bridge(bridge)
{
}

bool KaskadDecoration::init()
{
    updateLayout();

    connect(window(), &KDecoration3::DecoratedWindow::sizeChanged, this, [this]() {
        updateLayout();
        update();
    });
    connect(window(), &KDecoration3::DecoratedWindow::maximizedChanged, this, [this]() {
        updateLayout();
        update();
    });
    connect(window(), &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, [this]() {
        updateLayout();
        update();
    });
    connect(window(), &KDecoration3::DecoratedWindow::activeChanged, this, [this]() {
        updateLayout();
        update();
    });
    connect(window(), &KDecoration3::DecoratedWindow::captionChanged, this, qOverload<>(&KaskadDecoration::update));
    connect(window(), &KDecoration3::DecoratedWindow::onAllDesktopsChanged, this, [this]() {
        update(controlRect(Control::Pin));
    });
    connect(window(), &KDecoration3::DecoratedWindow::paletteChanged, this, qOverload<>(&KaskadDecoration::update));
    connect(m_bridge, &DecorationBridge::paletteChanged, this, [this]() {
        updateLayout();
        update();
    });
    return true;
}

void KaskadDecoration::updateLayout()
{
    const bool maximized = window()->isMaximized();
    const qreal titleHeight = maximized ? s_maximizedTitleHeight : s_titleHeight;
    const qreal visualBorder = maximized ? 0.0 : s_borderWidth;
    const qreal resizeBorder = maximized ? 0.0 : s_resizeMargin;

    setBorders(QMarginsF(visualBorder, titleHeight, visualBorder, visualBorder));
    setResizeOnlyBorders(QMarginsF(resizeBorder, 0.0, resizeBorder, resizeBorder));
    setTitleBar(QRectF(0.0, 0.0, size().width(), titleHeight));
    setBorderRadius(KDecoration3::BorderRadius(maximized ? 0.0 : s_cornerRadius));
    setBorderOutline(KDecoration3::BorderOutline(
        m_bridge->outlineEnabled() ? visualBorder : 0.0,
        m_bridge->outlineColor(window()->isActive()),
        KDecoration3::BorderRadius(maximized ? 0.0 : s_cornerRadius)));
    setOpaque(maximized);
}

QRectF KaskadDecoration::controlRect(Control control) const
{
    const qreal height = titleBar().height();
    if (control == Control::Pin) {
        return QRectF(2.0, 0.0, s_pinWidth, height);
    }
    const int index = control == Control::Close ? 0 : control == Control::Maximize ? 1 : 2;
    return QRectF(size().width() - s_controlWidth * (index + 1), 0.0, s_controlWidth, height);
}

KaskadDecoration::Control KaskadDecoration::controlAt(const QPointF &position) const
{
    for (Control control : {Control::Pin, Control::Close, Control::Maximize, Control::Minimize}) {
        if (controlRect(control).contains(position)) {
            return control;
        }
    }
    return Control::None;
}

void KaskadDecoration::paintControl(QPainter *painter, Control control, const QColor &foreground)
{
    const QRectF area = controlRect(control);
    if (control == m_hoveredControl || control == m_pressedControl) {
        const bool close = control == Control::Close;
        const QColor base = close ? m_bridge->errorColor() : (control == Control::Pin ? m_bridge->accentColor() : foreground);
        painter->setPen(Qt::NoPen);
        painter->setBrush(withAlpha(base, control == m_pressedControl ? 0.24 : 0.12));
        painter->drawRoundedRect(area.adjusted(4.0, 4.0, -4.0, -4.0), 8.0, 8.0);
    }

    const QPointF center = area.center();
    const QString symbolsFamily = materialSymbolsFamily();
    if (control == Control::Pin && !symbolsFamily.isEmpty()) {
        const bool pinned = window()->isOnAllDesktops();
        QFont iconFont(symbolsFamily);
        iconFont.setPixelSize(18);
        iconFont.setWeight(QFont::Normal);
        iconFont.setHintingPreference(QFont::PreferNoHinting);
        iconFont.setVariableAxis(QFont::Tag("FILL"), pinned ? 1.0f : 0.0f);
        iconFont.setVariableAxis(QFont::Tag("GRAD"), -25.0f);
        iconFont.setVariableAxis(QFont::Tag("opsz"), 20.0f);
        iconFont.setVariableAxis(QFont::Tag("wght"), 400.0f);

        painter->setFont(iconFont);
        painter->setPen(pinned ? m_bridge->accentColor() : foreground);
        painter->setBrush(Qt::NoBrush);
        painter->drawText(area, Qt::AlignCenter, QStringLiteral("push_pin"));
        return;
    }

    QPen pen(foreground, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    if (control == Control::Pin) {
        const bool pinned = window()->isOnAllDesktops();
        const QColor pinColor = pinned ? m_bridge->accentColor() : foreground;
        painter->setPen(QPen(pinColor, 1.5));
        painter->setBrush(pinned ? pinColor : Qt::NoBrush);
        painter->drawEllipse(center, 4.0, 4.0);
        if (!pinned) {
            painter->setPen(Qt::NoPen);
            painter->setBrush(withAlpha(pinColor, 0.55));
            painter->drawEllipse(center, 1.35, 1.35);
        }
    } else if (control == Control::Close) {
        painter->drawLine(center + QPointF(-4.25, -4.25), center + QPointF(4.25, 4.25));
        painter->drawLine(center + QPointF(4.25, -4.25), center + QPointF(-4.25, 4.25));
    } else if (control == Control::Maximize) {
        if (window()->isMaximized()) {
            // Four inward-facing corners communicate "restore" without using
            // the conventional pair of overlapping squares.
            painter->drawLine(center + QPointF(-5.0, -1.5), center + QPointF(-1.5, -1.5));
            painter->drawLine(center + QPointF(-1.5, -5.0), center + QPointF(-1.5, -1.5));
            painter->drawLine(center + QPointF(5.0, -1.5), center + QPointF(1.5, -1.5));
            painter->drawLine(center + QPointF(1.5, -5.0), center + QPointF(1.5, -1.5));
            painter->drawLine(center + QPointF(-5.0, 1.5), center + QPointF(-1.5, 1.5));
            painter->drawLine(center + QPointF(-1.5, 5.0), center + QPointF(-1.5, 1.5));
            painter->drawLine(center + QPointF(5.0, 1.5), center + QPointF(1.5, 1.5));
            painter->drawLine(center + QPointF(1.5, 5.0), center + QPointF(1.5, 1.5));
        } else {
            // Broken outward corners form Kaskad's own expand glyph.
            painter->drawLine(center + QPointF(-5.0, -1.5), center + QPointF(-5.0, -5.0));
            painter->drawLine(center + QPointF(-5.0, -5.0), center + QPointF(-1.5, -5.0));
            painter->drawLine(center + QPointF(5.0, -1.5), center + QPointF(5.0, -5.0));
            painter->drawLine(center + QPointF(5.0, -5.0), center + QPointF(1.5, -5.0));
            painter->drawLine(center + QPointF(-5.0, 1.5), center + QPointF(-5.0, 5.0));
            painter->drawLine(center + QPointF(-5.0, 5.0), center + QPointF(-1.5, 5.0));
            painter->drawLine(center + QPointF(5.0, 1.5), center + QPointF(5.0, 5.0));
            painter->drawLine(center + QPointF(5.0, 5.0), center + QPointF(1.5, 5.0));
        }
    } else if (control == Control::Minimize) {
        painter->drawLine(center + QPointF(-4.5, -1.75), center + QPointF(0.0, 2.25));
        painter->drawLine(center + QPointF(0.0, 2.25), center + QPointF(4.5, -1.75));
    }
}

void KaskadDecoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)

    const bool active = window()->isActive();
    const QColor background = m_bridge->surfaceColor(active);
    const QColor foreground = m_bridge->foregroundColor(active);
    const qreal radius = window()->isMaximized() ? 0.0 : s_cornerRadius;

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);

    QPainterPath frame;
    frame.addRoundedRect(rect(), radius, radius);
    painter->fillPath(frame, background);

    const QRectF title = titleBar();
    const qreal controlsWidth = 3.0 * s_controlWidth;
    const qreal captionLeft = s_pinWidth + 8.0;
    const QRectF captionArea(captionLeft, 0.0, std::max(0.0, title.width() - captionLeft - controlsWidth - 12.0), title.height());
    QFont titleFont = painter->font();
    const QString textFamily = interFamily();
    if (!textFamily.isEmpty()) {
        titleFont.setFamily(textFamily);
    }
    titleFont.setWeight(active ? QFont::DemiBold : QFont::Medium);
    titleFont.setPixelSize(13);
    titleFont.setHintingPreference(QFont::PreferNoHinting);
    painter->setFont(titleFont);
    painter->setPen(foreground);
    const QString caption = QFontMetricsF(titleFont).elidedText(window()->caption(), Qt::ElideRight, captionArea.width());
    painter->drawText(captionArea, Qt::AlignVCenter | Qt::AlignLeft, caption);

    paintControl(painter, Control::Pin, foreground);
    if (window()->isMinimizeable()) {
        paintControl(painter, Control::Minimize, foreground);
    }
    if (window()->isMaximizeable()) {
        paintControl(painter, Control::Maximize, foreground);
    }
    if (window()->isCloseable()) {
        paintControl(painter, Control::Close, foreground);
    }
    painter->restore();
}

void KaskadDecoration::mousePressEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        m_pressedControl = controlAt(event->position());
        if (m_pressedControl != Control::None) {
            event->accept();
            update(controlRect(m_pressedControl));
            return;
        }
    }
    KDecoration3::Decoration::mousePressEvent(event);
}

void KaskadDecoration::mouseReleaseEvent(QMouseEvent *event)
{
    const Control pressed = m_pressedControl;
    m_pressedControl = Control::None;
    if (pressed != Control::None) {
        update(controlRect(pressed));
        if (event->button() == Qt::LeftButton && controlAt(event->position()) == pressed) {
            if (pressed == Control::Pin) {
                requestToggleOnAllDesktops();
            } else if (pressed == Control::Close && window()->isCloseable()) {
                requestClose();
            } else if (pressed == Control::Maximize && window()->isMaximizeable()) {
                requestToggleMaximization(Qt::LeftButton);
            } else if (pressed == Control::Minimize && window()->isMinimizeable()) {
                requestMinimize();
            }
        }
        event->accept();
        return;
    }
    KDecoration3::Decoration::mouseReleaseEvent(event);
}

void KaskadDecoration::hoverMoveEvent(QHoverEvent *event)
{
    const Control hovered = controlAt(event->position());
    if (hovered != m_hoveredControl) {
        const Control previous = m_hoveredControl;
        m_hoveredControl = hovered;
        if (previous != Control::None) {
            update(controlRect(previous));
        }
        if (hovered != Control::None) {
            update(controlRect(hovered));
        }
    }
    KDecoration3::Decoration::hoverMoveEvent(event);
}

void KaskadDecoration::hoverLeaveEvent(QHoverEvent *event)
{
    if (m_hoveredControl != Control::None) {
        const Control previous = m_hoveredControl;
        m_hoveredControl = Control::None;
        update(controlRect(previous));
    }
    KDecoration3::Decoration::hoverLeaveEvent(event);
}

} // namespace KWin::Decoration

#include "moc_kaskaddecoration.cpp"
