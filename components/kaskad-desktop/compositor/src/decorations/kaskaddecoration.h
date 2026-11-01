/*
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KDecoration3/Decoration>

#include <QColor>
#include <QPointF>
#include <QVariantList>

namespace KWin::Decoration
{

class DecorationBridge;

class KaskadDecoration final : public KDecoration3::Decoration
{
    Q_OBJECT

public:
    explicit KaskadDecoration(QObject *parent, const QVariantList &args, DecorationBridge *bridge);

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintArea) override;

protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;
    void hoverLeaveEvent(QHoverEvent *event) override;

private:
    enum class Control {
        None,
        Pin,
        Minimize,
        Maximize,
        Close,
    };

    void updateLayout();
    Control controlAt(const QPointF &position) const;
    QRectF controlRect(Control control) const;
    void paintControl(QPainter *painter, Control control, const QColor &foreground);

    DecorationBridge *m_bridge = nullptr;
    Control m_pressedControl = Control::None;
    Control m_hoveredControl = Control::None;
};

} // namespace KWin::Decoration
