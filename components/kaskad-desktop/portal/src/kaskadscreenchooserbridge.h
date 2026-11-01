/*
    SPDX-License-Identifier: LGPL-2.0-or-later
    SPDX-FileCopyrightText: 2026 The KaskadDesktop contributors
*/

#pragma once

#include <QDBusContext>
#include <QObject>
#include <QHash>

class ScreenChooserDialog;

class KaskadScreenChooserBridge : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kaskados.ScreenCastChooser1")

public:
    static KaskadScreenChooserBridge *self();

    bool request(ScreenChooserDialog *dialog, const QString &title, const QString &optionsJson);
    void forget(ScreenChooserDialog *dialog);

public Q_SLOTS:
    bool select(const QString &requestId, const QString &kind, const QString &id, bool allowRestore);
    bool cancel(const QString &requestId);

Q_SIGNALS:
    void selectionRequested(const QString &requestId, const QString &title, const QString &optionsJson);

private:
    explicit KaskadScreenChooserBridge(QObject *parent = nullptr);
    bool isKaskadCaller() const;

    QHash<QString, ScreenChooserDialog *> m_requests;
};
