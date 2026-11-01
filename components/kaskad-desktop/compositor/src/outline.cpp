/*
    KWin - the KDE window manager
    This file is part of the KDE project.

    SPDX-FileCopyrightText: 2011 Arthur Arlt <a.arlt@stud.uni-heidelberg.de>
    SPDX-FileCopyrightText: 2013 Martin Gräßlin <mgraesslin@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// own
#include "outline.h"
// KWin
#include "decorations/decorationbridge.h"
#include "main.h"
#include "scene/borderoutline.h"
#include "scene/borderradius.h"
#include "scene/outlinedborderitem.h"
#include "scene/workspacescene.h"
#include "workspace.h"

namespace KWin
{

Outline::Outline()
    : m_active(false)
{
}

Outline::~Outline() = default;

void Outline::show()
{
    if (!m_visual) {
        createHelper();
    }
    if (!m_visual) {
        // something went wrong
        return;
    }
    m_visual->show();
    m_active = true;
    Q_EMIT activeChanged();
}

void Outline::hide()
{
    if (!m_active) {
        return;
    }
    m_active = false;
    Q_EMIT activeChanged();
    if (!m_visual) {
        return;
    }
    m_visual->hide();
}

void Outline::show(const Rect &outlineGeometry)
{
    show(outlineGeometry, Rect());
}

void Outline::show(const Rect &outlineGeometry, const Rect &visualParentGeometry)
{
    setGeometry(outlineGeometry);
    setVisualParentGeometry(visualParentGeometry);
    show();
}

void Outline::setGeometry(const Rect &outlineGeometry)
{
    if (m_outlineGeometry == outlineGeometry) {
        return;
    }
    m_outlineGeometry = outlineGeometry;
    Q_EMIT geometryChanged();
    Q_EMIT unifiedGeometryChanged();
}

void Outline::setVisualParentGeometry(const Rect &visualParentGeometry)
{
    if (m_visualParentGeometry == visualParentGeometry) {
        return;
    }
    m_visualParentGeometry = visualParentGeometry;
    Q_EMIT visualParentGeometryChanged();
    Q_EMIT unifiedGeometryChanged();
}

Rect Outline::unifiedGeometry() const
{
    return m_outlineGeometry | m_visualParentGeometry;
}

void Outline::createHelper()
{
    if (m_visual) {
        return;
    }
    m_visual = std::make_unique<OutlineVisual>(this);
}

const Rect &Outline::geometry() const
{
    return m_outlineGeometry;
}

const Rect &Outline::visualParentGeometry() const
{
    return m_visualParentGeometry;
}

bool Outline::isActive() const
{
    return m_active;
}
OutlineVisual::OutlineVisual(Outline *outline)
    : m_outline(outline)
{
}

OutlineVisual::~OutlineVisual()
{
}

void OutlineVisual::hide()
{
    if (m_item) {
        m_item->setVisible(false);
    }
}

void OutlineVisual::show()
{
    const QColor accent = workspace()->decorationBridge()->accentColor();
    const BorderOutline border(2.0, accent, BorderRadius(10.0));
    if (!m_item) {
        m_item = std::make_unique<OutlinedBorderItem>(m_outline->geometry(), border, kwinApp()->scene()->overlayItem());
    } else {
        m_item->setInnerRect(m_outline->geometry());
        m_item->setOutline(border);
    }
    m_item->setVisible(true);
    m_item->scheduleSceneRepaint(m_item->boundingRect());
}

} // namespace

#include "moc_outline.cpp"
