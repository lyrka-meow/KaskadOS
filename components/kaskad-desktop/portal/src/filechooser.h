/*
 * SPDX-FileCopyrightText: 2016-2018 Red Hat Inc
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 *
 * SPDX-FileCopyrightText: 2016-2018 Jan Grulich <jgrulich@redhat.com>
 */

#ifndef XDG_DESKTOP_PORTAL_KDE_FILECHOOSER_H
#define XDG_DESKTOP_PORTAL_KDE_FILECHOOSER_H

#include "dbushelpers.h"

#include <QCheckBox>
#include <QComboBox>
#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QFileDialog>

class QDBusMessage;

class FileDialog : public QFileDialog
{
    Q_OBJECT
public:
    explicit FileDialog(QWidget *parent = nullptr, Qt::WindowFlags flags = {});
    Q_DISABLE_COPY_MOVE(FileDialog)

    void setChoiceWidget(QWidget *widget);
};

class FileChooserPortal : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.FileChooser")
public:
    // Keep in sync with qflatpakfiledialog from flatpak-platform-plugin
    typedef struct {
        uint type;
        QString filterString;
    } Filter;
    typedef QList<Filter> Filters;

    typedef struct {
        QString userVisibleName;
        Filters filters;
    } FilterList;
    typedef QList<FilterList> FilterListList;

    explicit FileChooserPortal(QObject *parent);

public Q_SLOTS:
    void OpenFile(const QDBusObjectPath &handle,
                  const QString &app_id,
                  const QString &parent_window,
                  const QString &title,
                  const QVariantMap &options,
                  const QDBusMessage &message,
                  uint &replyResponse,
                  QVariantMap &replyResults);

    void SaveFile(const QDBusObjectPath &handle,
                  const QString &app_id,
                  const QString &parent_window,
                  const QString &title,
                  const QVariantMap &options,
                  const QDBusMessage &message,
                  uint &replyResponse,
                  QVariantMap &replyResults);

private:
    static QWidget *CreateChoiceControls(const OptionList &optionList, QMap<QString, QCheckBox *> &checkboxes, QMap<QString, QComboBox *> &comboboxes);

    static QVariant EvaluateSelectedChoices(const QMap<QString, QCheckBox *> &checkboxes, const QMap<QString, QComboBox *> &comboboxes);

    static QString ExtractAcceptLabel(const QVariantMap &options);

    struct FilterExtract {
        QStringList filters;
        QString currentFilter;
        QMap<QString, FilterList> portalFilters;
    };

    static FilterExtract ExtractFilters(const QVariantMap &options);

    static QString filterListToNameFilter(const FilterList &list);
};

#endif // XDG_DESKTOP_PORTAL_KDE_FILECHOOSER_H
