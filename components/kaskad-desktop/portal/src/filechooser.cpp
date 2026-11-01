/*
 * SPDX-FileCopyrightText: 2016-2018 Red Hat Inc
 * SPDX-FileCopyrightText: 2016-2018 Jan Grulich <jgrulich@redhat.com>
 * SPDX-FileCopyrightText: 2026 KaskadOS contributors
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

#include "filechooser.h"
#include "filechooser_debug.h"
#include "request.h"
#include "utils.h"

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDir>
#include <QFile>
#include <QGridLayout>
#include <QLabel>
#include <QMimeDatabase>
#include <QUrl>

Q_DECLARE_METATYPE(FileChooserPortal::Filter)
Q_DECLARE_METATYPE(FileChooserPortal::Filters)
Q_DECLARE_METATYPE(FileChooserPortal::FilterList)
Q_DECLARE_METATYPE(FileChooserPortal::FilterListList)

QDBusArgument &operator<<(QDBusArgument &arg, const FileChooserPortal::Filter &filter)
{
    arg.beginStructure();
    arg << filter.type << filter.filterString;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, FileChooserPortal::Filter &filter)
{
    arg.beginStructure();
    arg >> filter.type >> filter.filterString;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const FileChooserPortal::FilterList &filterList)
{
    arg.beginStructure();
    arg << filterList.userVisibleName << filterList.filters;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, FileChooserPortal::FilterList &filterList)
{
    arg.beginStructure();
    arg >> filterList.userVisibleName >> filterList.filters;
    arg.endStructure();
    return arg;
}

static QString decodeFileName(const QByteArray &name)
{
    QByteArray decodedName = name;
    while (decodedName.endsWith('\0')) {
        decodedName.chop(1);
    }
    return QFile::decodeName(decodedName);
}

static QStringList encodedUrls(const QList<QUrl> &urls)
{
    // KaskadOS deliberately exposes only local paths. Remote filesystem
    // adapters do not belong in the desktop portal process.
    return QUrl::toStringList(urls, QUrl::FullyEncoded);
}

FileDialog::FileDialog(QWidget *parent, Qt::WindowFlags flags)
    : QFileDialog(parent, flags)
{
    setOption(QFileDialog::DontUseNativeDialog, true);
    setSupportedSchemes({QStringLiteral("file")});
}

void FileDialog::setChoiceWidget(QWidget *widget)
{
    if (widget) {
        layout()->addWidget(widget);
    }
}

FileChooserPortal::FileChooserPortal(QObject *parent)
    : QDBusAbstractAdaptor(parent)
{
    qDBusRegisterMetaType<Filter>();
    qDBusRegisterMetaType<Filters>();
    qDBusRegisterMetaType<FilterList>();
    qDBusRegisterMetaType<FilterListList>();
    qDBusRegisterMetaType<Choice>();
    qDBusRegisterMetaType<Choices>();
    qDBusRegisterMetaType<Option>();
    qDBusRegisterMetaType<OptionList>();
}

QString FileChooserPortal::filterListToNameFilter(const FilterList &filterList)
{
    QStringList patterns;
    const QMimeDatabase mimeDatabase;
    for (const Filter &filter : filterList.filters) {
        if (filter.type == 0) {
            patterns << filter.filterString;
        } else {
            const QMimeType mime = mimeDatabase.mimeTypeForName(filter.filterString);
            if (mime.isValid()) {
                patterns << mime.globPatterns();
            }
        }
    }
    patterns.removeDuplicates();
    if (patterns.isEmpty()) {
        patterns << QStringLiteral("*");
    }
    return QStringLiteral("%1 (%2)").arg(filterList.userVisibleName, patterns.join(QLatin1Char(' ')));
}

void FileChooserPortal::OpenFile(const QDBusObjectPath &handle,
                                 const QString &app_id,
                                 const QString &parent_window,
                                 const QString &title,
                                 const QVariantMap &options,
                                 const QDBusMessage &message,
                                 uint &replyResponse,
                                 QVariantMap &replyResults)
{
    Q_UNUSED(app_id)
    Q_UNUSED(replyResponse)
    Q_UNUSED(replyResults)

    const bool directory = options.value(QStringLiteral("directory"), false).toBool();
    const bool multiple = options.value(QStringLiteral("multiple"), false).toBool();
    const bool modal = options.value(QStringLiteral("modal"), true).toBool();
    const QString acceptLabel = ExtractAcceptLabel(options);
    QString currentFolder = decodeFileName(options.value(QStringLiteral("current_folder")).toByteArray());
    if (!currentFolder.isEmpty() && QDir::isRelativePath(currentFolder)) {
        currentFolder.clear();
    }

    const FilterExtract filterData = ExtractFilters(options);
    auto *dialog = new FileDialog;
    dialog->setWindowTitle(title);
    dialog->setAcceptMode(QFileDialog::AcceptOpen);
    dialog->setFileMode(directory ? QFileDialog::Directory : multiple ? QFileDialog::ExistingFiles : QFileDialog::ExistingFile);
    dialog->setOption(QFileDialog::ShowDirsOnly, directory);
    if (!currentFolder.isEmpty()) {
        dialog->setDirectory(currentFolder);
    }
    if (!filterData.filters.isEmpty()) {
        dialog->setNameFilters(filterData.filters);
    }
    if (!filterData.currentFilter.isEmpty()) {
        dialog->selectNameFilter(filterData.currentFilter);
    }
    if (!acceptLabel.isEmpty()) {
        dialog->setLabelText(QFileDialog::Accept, acceptLabel);
    }

    QWidget *optionsWidget = nullptr;
    QMap<QString, QCheckBox *> checkboxes;
    QMap<QString, QComboBox *> comboboxes;
    if (options.contains(QStringLiteral("choices"))) {
        optionsWidget = CreateChoiceControls(qdbus_cast<OptionList>(options.value(QStringLiteral("choices"))), checkboxes, comboboxes);
        dialog->setChoiceWidget(optionsWidget);
    }

    dialog->winId();
    Utils::setParentWindow(dialog, parent_window);
    Request::makeClosableDialogRequest(handle, dialog);
    dialog->setWindowModality(modal ? Qt::WindowModal : Qt::NonModal);

    delayReply(message, dialog, this, [dialog, optionsWidget, checkboxes, comboboxes, filterData](int result) -> QVariantList {
        QVariantMap results;
        if (result == QDialog::Accepted && !dialog->selectedUrls().isEmpty()) {
            results.insert(QStringLiteral("uris"), encodedUrls(dialog->selectedUrls()));
            results.insert(QStringLiteral("writable"), true);
            if (optionsWidget) {
                results.insert(QStringLiteral("choices"), EvaluateSelectedChoices(checkboxes, comboboxes));
            }
            const QString selectedFilter = dialog->selectedNameFilter();
            if (filterData.portalFilters.contains(selectedFilter)) {
                results.insert(QStringLiteral("current_filter"), QVariant::fromValue(filterData.portalFilters.value(selectedFilter)));
            }
        }
        dialog->deleteLater();
        return {PortalResponse::fromDialogCode(static_cast<QDialog::DialogCode>(result)), results};
    });
    dialog->open();
}

void FileChooserPortal::SaveFile(const QDBusObjectPath &handle,
                                 const QString &app_id,
                                 const QString &parent_window,
                                 const QString &title,
                                 const QVariantMap &options,
                                 const QDBusMessage &message,
                                 uint &replyResponse,
                                 QVariantMap &replyResults)
{
    Q_UNUSED(app_id)
    Q_UNUSED(replyResponse)
    Q_UNUSED(replyResults)

    const bool modal = options.value(QStringLiteral("modal"), true).toBool();
    const QString acceptLabel = ExtractAcceptLabel(options);
    const QString currentName = options.value(QStringLiteral("current_name")).toString();
    QString currentFolder = decodeFileName(options.value(QStringLiteral("current_folder")).toByteArray());
    const QString currentFile = decodeFileName(options.value(QStringLiteral("current_file")).toByteArray());
    if (!currentFolder.isEmpty() && QDir::isRelativePath(currentFolder)) {
        currentFolder.clear();
    }

    const FilterExtract filterData = ExtractFilters(options);
    auto *dialog = new FileDialog;
    dialog->setWindowTitle(title);
    dialog->setAcceptMode(QFileDialog::AcceptSave);
    dialog->setFileMode(QFileDialog::AnyFile);
    if (!currentFolder.isEmpty()) {
        dialog->setDirectory(currentFolder);
    }
    if (!currentFile.isEmpty()) {
        dialog->selectFile(currentFile);
    } else if (!currentName.isEmpty()) {
        dialog->selectFile(currentName);
    }
    if (!filterData.filters.isEmpty()) {
        dialog->setNameFilters(filterData.filters);
    }
    if (!filterData.currentFilter.isEmpty()) {
        dialog->selectNameFilter(filterData.currentFilter);
    }
    if (!acceptLabel.isEmpty()) {
        dialog->setLabelText(QFileDialog::Accept, acceptLabel);
    }

    QWidget *optionsWidget = nullptr;
    QMap<QString, QCheckBox *> checkboxes;
    QMap<QString, QComboBox *> comboboxes;
    if (options.contains(QStringLiteral("choices"))) {
        optionsWidget = CreateChoiceControls(qdbus_cast<OptionList>(options.value(QStringLiteral("choices"))), checkboxes, comboboxes);
        dialog->setChoiceWidget(optionsWidget);
    }

    dialog->winId();
    Utils::setParentWindow(dialog, parent_window);
    Request::makeClosableDialogRequest(handle, dialog);
    dialog->setWindowModality(modal ? Qt::WindowModal : Qt::NonModal);

    delayReply(message, dialog, this, [dialog, optionsWidget, checkboxes, comboboxes, filterData](int result) -> QVariantList {
        QVariantMap results;
        if (result == QDialog::Accepted && !dialog->selectedUrls().isEmpty()) {
            results.insert(QStringLiteral("uris"), encodedUrls(dialog->selectedUrls()));
            if (optionsWidget) {
                results.insert(QStringLiteral("choices"), EvaluateSelectedChoices(checkboxes, comboboxes));
            }
            const QString selectedFilter = dialog->selectedNameFilter();
            if (filterData.portalFilters.contains(selectedFilter)) {
                results.insert(QStringLiteral("current_filter"), QVariant::fromValue(filterData.portalFilters.value(selectedFilter)));
            }
        }
        dialog->deleteLater();
        return QVariantList{PortalResponse::fromDialogCode(static_cast<QDialog::DialogCode>(result)), results};
    });
    dialog->open();
}

QWidget *FileChooserPortal::CreateChoiceControls(const OptionList &optionList,
                                                 QMap<QString, QCheckBox *> &checkboxes,
                                                 QMap<QString, QComboBox *> &comboboxes)
{
    if (optionList.empty()) {
        return nullptr;
    }

    auto *optionsWidget = new QWidget;
    auto *layout = new QGridLayout(optionsWidget);
    layout->setColumnStretch(2, 1);
    for (const Option &option : optionList) {
        const int row = layout->rowCount();
        if (option.choices.empty()) {
            auto *checkbox = new QCheckBox(option.label, optionsWidget);
            checkbox->setChecked(option.initialChoiceId == QStringLiteral("true"));
            layout->addWidget(checkbox, row, 1);
            checkboxes.insert(option.id, checkbox);
            continue;
        }

        auto *combobox = new QComboBox(optionsWidget);
        for (const Choice &choice : option.choices) {
            combobox->addItem(choice.value, choice.id);
            if (choice.id == option.initialChoiceId) {
                combobox->setCurrentIndex(combobox->count() - 1);
            }
        }
        QString labelText = option.label;
        if (!labelText.endsWith(QLatin1Char(':'))) {
            labelText += QLatin1Char(':');
        }
        auto *label = new QLabel(labelText, optionsWidget);
        label->setBuddy(combobox);
        layout->addWidget(label, row, 0, Qt::AlignRight);
        layout->addWidget(combobox, row, 1);
        comboboxes.insert(option.id, combobox);
    }
    return optionsWidget;
}

QVariant FileChooserPortal::EvaluateSelectedChoices(const QMap<QString, QCheckBox *> &checkboxes,
                                                     const QMap<QString, QComboBox *> &comboboxes)
{
    Choices choices;
    for (auto it = checkboxes.cbegin(); it != checkboxes.cend(); ++it) {
        choices << Choice{it.key(), it.value()->isChecked() ? QStringLiteral("true") : QStringLiteral("false")};
    }
    for (auto it = comboboxes.cbegin(); it != comboboxes.cend(); ++it) {
        choices << Choice{it.key(), it.value()->currentData().toString()};
    }
    return QVariant::fromValue<Choices>(choices);
}

QString FileChooserPortal::ExtractAcceptLabel(const QVariantMap &options)
{
    QString label = options.value(QStringLiteral("accept_label")).toString();
    label.replace(QLatin1Char('&'), QStringLiteral("&&"));
    const qsizetype mnemonic = label.indexOf(QLatin1Char('_'));
    if (mnemonic >= 0) {
        label.replace(mnemonic, 1, QLatin1Char('&'));
    }
    return label;
}

FileChooserPortal::FilterExtract FileChooserPortal::ExtractFilters(const QVariantMap &options)
{
    FilterExtract result;
    const FilterListList portalFilters = qdbus_cast<FilterListList>(options.value(QStringLiteral("filters")));
    for (const FilterList &filter : portalFilters) {
        const QString nameFilter = filterListToNameFilter(filter);
        result.filters << nameFilter;
        result.portalFilters.insert(nameFilter, filter);
    }

    if (options.contains(QStringLiteral("current_filter"))) {
        const FilterList current = qdbus_cast<FilterList>(options.value(QStringLiteral("current_filter")));
        if (!current.filters.isEmpty()) {
            result.currentFilter = filterListToNameFilter(current);
            result.portalFilters.insert(result.currentFilter, current);
        }
    }
    return result;
}

#include "moc_filechooser.cpp"
