#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QHeaderView>
#include <QLabel>
#include <QMainWindow>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QProcess>
#include <QProcessEnvironment>
#include <QProgressBar>
#include <QPushButton>
#include <QStackedWidget>
#include <QTextCursor>
#include <QTreeWidget>
#include <QVBoxLayout>

namespace {
constexpr int KindRole = Qt::UserRole;
constexpr int NameRole = Qt::UserRole + 1;
constexpr int LocalVersionRole = Qt::UserRole + 2;
constexpr int OwnersRole = Qt::UserRole + 3;
constexpr int PackageContainerRole = Qt::UserRole + 4;
constexpr int RootPackageRole = Qt::UserRole + 5;

QString inferProjectDirectory()
{
    if (QFileInfo::exists(QDir::currentPath() + "/profile/packages.x86_64"))
        return QDir::currentPath();
    QDir directory(QCoreApplication::applicationDirPath());
    if (directory.cdUp() && directory.cdUp()
        && QFileInfo::exists(directory.filePath("profile/packages.x86_64")))
        return directory.absolutePath();
    return QDir::currentPath();
}

QStringList readPackageList(const QString& path)
{
    QFile file(path);
    QStringList result;
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return result;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (!line.isEmpty() && !line.startsWith('#')) result.append(line);
    }
    result.removeDuplicates();
    result.sort(Qt::CaseInsensitive);
    return result;
}

QHash<QString, QString> readResolvedPackages(const QString& path)
{
    QFile file(path);
    QHash<QString, QString> result;
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return result;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        const QString package = line.section('\t', 0, 0).trimmed();
        const QString version = line.section('\t', 1, 1).trimmed();
        if (!package.isEmpty() && !package.startsWith('#') && !version.isEmpty())
            result.insert(package, version);
    }
    return result;
}

QString readAssignment(const QString& path, const QString& key)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return {};
    const QByteArray prefix = key.toUtf8() + '=';
    while (!file.atEnd()) {
        const QByteArray line = file.readLine().trimmed();
        if (line.startsWith(prefix)) return QString::fromUtf8(line.mid(prefix.size()));
    }
    return {};
}

using OwnerRules = QList<QPair<QString, QStringList>>;

OwnerRules readOwnerRules(const QString& path)
{
    QFile file(path);
    OwnerRules rules;
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return rules;
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.isEmpty() || line.startsWith('#')) continue;
        const qsizetype separator = line.indexOf(':');
        if (separator <= 0) continue;
        const QString owner = line.left(separator).trimmed();
        const QStringList patterns = line.mid(separator + 1).simplified().split(' ', Qt::SkipEmptyParts);
        if (!owner.isEmpty() && !patterns.isEmpty()) rules.append({owner, patterns});
    }
    return rules;
}

QStringList ownersForPackage(const QString& package, const OwnerRules& rules)
{
    QStringList owners;
    for (const auto& [owner, patterns] : rules) {
        for (const QString& pattern : patterns) {
            if (!QDir::match(pattern, package)) continue;
            if (!owners.contains(owner)) owners.append(owner);
            break;
        }
    }
    if (owners.isEmpty()) owners.append("base");
    return owners;
}

QString familyForPackage(const QString& package, const OwnerRules& rules)
{
    for (const auto& [family, patterns] : rules)
        for (const QString& pattern : patterns)
            if (QDir::match(pattern, package)) return family;
    return "other";
}

QString ownerDisplayName(const QString& owner)
{
    static const QHash<QString, QString> names = {
        {"installer", "Установщик"},
        {"installer.calamares", "Calamares"},
        {"installer.compositor", "Композитор установщика"},
        {"desktop", "Kaskad DE"},
        {"desktop.compositor", "Композитор"},
        {"desktop.portal", "Портал рабочего стола"},
        {"desktop.shell", "Оболочка"},
        {"desktop.integration", "Интеграция системы"},
        {"regalia", "Regalia VPN"},
        {"bootloaders", "Загрузчики"},
        {"graphics", "Графика и драйверы"},
        {"network", "Сеть"},
        {"storage", "Диски и файловые системы"},
        {"base", "Базовая Live-система"}
    };
    return names.value(owner, owner);
}

QString familyDisplayName(const QString& family)
{
    static const QHash<QString, QString> names = {
        {"qt6", "Семейство Qt 6"},
        {"kde", "Семейство KDE Frameworks"},
        {"wayland", "Wayland и графика"},
        {"fonts", "Шрифты и оформление"},
        {"network", "Сеть"},
        {"storage", "Диски и файловые системы"},
        {"boot", "Загрузка системы"},
        {"tools", "Приложения и инструменты"},
        {"system", "Системные библиотеки"},
        {"other", "Прочее"}
    };
    return names.value(family, family);
}

QString ownersDisplayText(const QStringList& owners)
{
    QStringList names;
    for (const QString& owner : owners) names.append(ownerDisplayName(owner));
    return names.join(", ");
}

QString packageDisplayName(const QString& package)
{
    if (package == "grub") return "grub — GRUB, загрузчик устанавливаемой системы";
    if (package == "refind") return "refind — rEFInd, альтернативный UEFI-загрузчик";
    if (package == "syslinux") return "syslinux — загрузчик BIOS";
    if (package == "efibootmgr") return "efibootmgr — создание загрузочной записи UEFI";
    if (package == "edk2-shell") return "edk2-shell — инструменты UEFI";
    if (package == "memtest86+-efi") return "memtest86+-efi — Memtest86+ UEFI";
    if (package == "memtest86+") return "memtest86+ — Memtest86+ BIOS";
    return package;
}
}

class ManagerWindow final : public QMainWindow
{
public:
    explicit ManagerWindow(QString projectDirectory)
        : m_projectDirectory(QDir(projectDirectory).absolutePath())
        , m_ownerRules(readOwnerRules(m_projectDirectory + "/profile/package-owners.conf"))
        , m_familyRules(readOwnerRules(m_projectDirectory + "/profile/package-families.conf"))
    {
        setWindowTitle("KaskadOS Manager");
        resize(1120, 760);
        m_pages = new QStackedWidget(this);
        setCentralWidget(m_pages);
        createMenuPage();
        createBuildPage();
        refreshLocalState();
    }

private:
    void createMenuPage()
    {
        auto* page = new QWidget;
        auto* layout = new QVBoxLayout(page);
        auto* title = new QLabel("KaskadOS Manager");
        QFont font = title->font();
        font.setPointSize(font.pointSize() + 6);
        font.setBold(true);
        title->setFont(font);
        auto* description = new QLabel("Выберите действие.");
        auto* build = new QPushButton("Сборка");
        auto* quit = new QPushButton("Выход");
        build->setMinimumSize(260, 42);
        quit->setMinimumSize(260, 42);
        layout->addStretch();
        layout->addWidget(title, 0, Qt::AlignHCenter);
        layout->addWidget(description, 0, Qt::AlignHCenter);
        layout->addSpacing(16);
        layout->addWidget(build, 0, Qt::AlignHCenter);
        layout->addWidget(quit, 0, Qt::AlignHCenter);
        layout->addStretch();
        connect(build, &QPushButton::clicked, this, [this] {
            refreshLocalState();
            m_pages->setCurrentWidget(m_buildPage);
        });
        connect(quit, &QPushButton::clicked, qApp, &QApplication::quit);
        m_pages->addWidget(page);
    }

    void createBuildPage()
    {
        m_buildPage = new QWidget;
        auto* layout = new QVBoxLayout(m_buildPage);
        auto* headingRow = new QHBoxLayout;
        auto* back = new QPushButton("Назад в меню");
        auto* heading = new QLabel("Сборка KaskadOS ISO");
        QFont font = heading->font();
        font.setPointSize(font.pointSize() + 4);
        font.setBold(true);
        heading->setFont(font);
        headingRow->addWidget(back);
        headingRow->addWidget(heading);
        headingRow->addStretch();
        layout->addLayout(headingRow);
        m_tree = new QTreeWidget;
        m_tree->setColumnCount(7);
        m_tree->setHeaderLabels({"Состав ISO", "Используется", "Локально", "Доступно",
                                 "Состояние", "Проверка", "Действие"});
        m_tree->setAlternatingRowColors(true);
        m_tree->setSelectionMode(QAbstractItemView::ExtendedSelection);
        m_tree->header()->setSectionResizeMode(0, QHeaderView::Stretch);
        for (int column = 1; column < 7; ++column)
            m_tree->header()->setSectionResizeMode(column, QHeaderView::ResizeToContents);
        layout->addWidget(m_tree, 1);

        auto* selectionRow = new QHBoxLayout;
        auto* selectAll = new QPushButton("Выбрать все пакеты");
        auto* clearSelection = new QPushButton("Снять выбор пакетов");
        auto* refresh = new QPushButton("Обновить локальное состояние");
        auto* checkSelected = new QPushButton("Проверить выбранные");
        auto* checkAll = new QPushButton("Проверить все");
        auto* validateCache = new QPushButton("Проверить локальный кэш");
        auto* downloadSelected = new QPushButton("Скачать / обновить выбранные");
        auto* downloadAll = new QPushButton("Обновить полный кэш");
        selectionRow->addWidget(selectAll);
        selectionRow->addWidget(clearSelection);
        selectionRow->addWidget(refresh);
        selectionRow->addStretch();
        selectionRow->addWidget(checkSelected);
        selectionRow->addWidget(checkAll);
        selectionRow->addWidget(validateCache);
        selectionRow->addWidget(downloadSelected);
        selectionRow->addWidget(downloadAll);
        layout->addLayout(selectionRow);

        auto* componentRow = new QHBoxLayout;
        auto* selectAllComponents = new QPushButton("Выбрать все компоненты");
        auto* clearComponents = new QPushButton("Снять выбор компонентов");
        m_buildSelected = new QPushButton("Собрать выбранные компоненты");
        componentRow->addWidget(selectAllComponents);
        componentRow->addWidget(clearComponents);
        componentRow->addStretch();
        componentRow->addWidget(m_buildSelected);
        layout->addLayout(componentRow);

        auto* buildRow = new QHBoxLayout;
        m_packageProfile = new QPushButton("Упаковать готовые компоненты в профиль ISO");
        m_buildIso = new QPushButton("Собрать ISO из локального кэша");
        m_stop = new QPushButton("Остановить");
        m_stop->setEnabled(false);
        buildRow->addWidget(m_packageProfile);
        buildRow->addStretch();
        buildRow->addWidget(m_buildIso);
        buildRow->addWidget(m_stop);
        layout->addLayout(buildRow);

        m_progress = new QProgressBar;
        m_progress->setRange(0, 1);
        m_progress->setValue(0);
        layout->addWidget(m_progress);
        m_log = new QPlainTextEdit;
        m_log->setReadOnly(true);
        m_log->setMaximumBlockCount(4000);
        m_log->setPlaceholderText("Вывод команды появится здесь.");
        layout->addWidget(m_log);
        m_pages->addWidget(m_buildPage);

        connect(back, &QPushButton::clicked, this, [this] { m_pages->setCurrentIndex(0); });
        connect(selectAll, &QPushButton::clicked, this, [this] {
            for (auto* item : std::as_const(m_packageItems)) item->setCheckState(0, Qt::Checked);
        });
        connect(clearSelection, &QPushButton::clicked, this, [this] {
            for (auto* item : std::as_const(m_packageItems)) item->setCheckState(0, Qt::Unchecked);
        });
        connect(refresh, &QPushButton::clicked, this, [this] { refreshLocalState(); });
        connect(checkSelected, &QPushButton::clicked, this, [this] {
            const QStringList packages = selectedPackages();
            if (packages.isEmpty()) {
                QMessageBox::information(this, "Ничего не выбрано",
                                         "Отметьте хотя бы один пакет для проверки.");
                return;
            }
            checkPackages(packages);
        });
        connect(checkAll, &QPushButton::clicked, this, [this] { checkPackages({}); });
        connect(validateCache, &QPushButton::clicked, this, [this] {
            runCommand("Офлайн-проверка локального кэша", "bash",
                       {m_projectDirectory + "/scripts/validate-iso-cache.sh"}, true);
        });
        connect(downloadSelected, &QPushButton::clicked, this, [this] { downloadPackages(selectedPackages()); });
        connect(downloadAll, &QPushButton::clicked, this, [this] { downloadAllPackages(); });
        connect(selectAllComponents, &QPushButton::clicked, this, [this] {
            for (auto* item : std::as_const(m_buildableItems)) item->setCheckState(0, Qt::Checked);
        });
        connect(clearComponents, &QPushButton::clicked, this, [this] {
            for (auto* item : std::as_const(m_buildableItems)) item->setCheckState(0, Qt::Unchecked);
        });
        connect(m_buildSelected, &QPushButton::clicked, this, [this] {
            const QStringList components = selectedComponents();
            if (components.isEmpty()) {
                QMessageBox::information(this, "Ничего не выбрано",
                                         "Отметьте хотя бы один компонент для пересборки.");
                return;
            }
            QStringList arguments = {m_projectDirectory + "/scripts/build-selected-components.sh"};
            arguments.append(components);
            runCommand("Пересборка выбранных компонентов", "bash", arguments, true);
        });
        connect(m_packageProfile, &QPushButton::clicked, this, [this] {
            runCommand("Упаковка готовых компонентов в профиль ISO", "bash",
                       {m_projectDirectory + "/scripts/package-ready-components.sh"}, true);
        });
        connect(m_buildIso, &QPushButton::clicked, this, [this] { buildIso(); });
        connect(m_stop, &QPushButton::clicked, this, [this] {
            if (m_process) m_process->terminate();
        });
    }

    QTreeWidgetItem* makeGroup(const QString& name, QTreeWidgetItem* parent = nullptr)
    {
        auto* item = parent ? new QTreeWidgetItem(parent) : new QTreeWidgetItem(m_tree);
        item->setText(0, name);
        item->setData(0, KindRole, "group");
        QFont font = item->font(0);
        font.setBold(true);
        item->setFont(0, font);
        return item;
    }

    QTreeWidgetItem* addComponent(QTreeWidgetItem* parent, const QString& name,
                                  const QString& sourcePath, const QString& resultPath,
                                  const QString& buildTarget, const QString& pinnedVersion = {},
                                  bool canCheckUpdate = false)
    {
        auto* item = new QTreeWidgetItem(parent);
        item->setText(0, name);
        item->setData(0, KindRole, "component");
        item->setData(0, NameRole, buildTarget);
        if (buildTarget != "sing-box") {
            item->setCheckState(0, Qt::Unchecked);
            m_buildableItems.insert(buildTarget, item);
        }
        const bool sourceExists = QFileInfo::exists(m_projectDirectory + '/' + sourcePath);
        const bool built = QFileInfo::exists(m_projectDirectory + '/' + resultPath);
        item->setText(1, "компонент ISO");
        item->setText(2, built ? (pinnedVersion.isEmpty() ? "есть сборка" : pinnedVersion) : "—");
        item->setData(0, LocalVersionRole, pinnedVersion);
        item->setText(3, pinnedVersion.isEmpty() ? "—" : "не проверялась");
        item->setText(4, !sourceExists ? "нет исходников"
                                      : built ? (buildTarget == "sing-box" ? "скачан" : "собран")
                                              : (buildTarget == "sing-box" ? "не скачан" : "не собран"));
        m_componentItems.insert(buildTarget, item);
        if (canCheckUpdate) {
            auto* check = new QPushButton("Проверить");
            m_tree->setItemWidget(item, 5, check);
            connect(check, &QPushButton::clicked, this, [this, buildTarget, name] {
                runCommand("Проверка обновления: " + name, "bash",
                           {m_projectDirectory + "/scripts/check-external-component.sh", buildTarget},
                           false, true);
            });
        }
        auto* rebuild = new QPushButton(buildTarget == "sing-box" ? "Скачать" : "Собрать");
        m_tree->setItemWidget(item, 6, rebuild);
        connect(rebuild, &QPushButton::clicked, this, [this, buildTarget, name] {
            if (buildTarget == "sing-box")
                runCommand("Обновление: " + name, "bash",
                           {m_projectDirectory + "/scripts/update-sing-box.sh"}, true);
            else
                runCommand("Пересборка: " + name, "bash",
                           {m_projectDirectory + "/scripts/build-component.sh", buildTarget}, true);
        });
        return item;
    }

    QTreeWidgetItem* makePackageContainer(const QString& key, const QString& label,
                                          QTreeWidgetItem* parent)
    {
        auto* item = makeGroup(label, parent);
        item->setData(0, PackageContainerRole, true);
        item->setData(0, NameRole, label);
        m_groups.insert(key, item);
        return item;
    }

    void expandGroupDescendants(QTreeWidgetItem* item)
    {
        for (int index = 0; index < item->childCount(); ++index) {
            auto* child = item->child(index);
            if (child->data(0, KindRole).toString() != "group") continue;
            child->setExpanded(true);
            expandGroupDescendants(child);
        }
    }

    void updatePackageContainerCounts(QTreeWidgetItem* item)
    {
        if (item->data(0, PackageContainerRole).toBool()) {
            const QString label = item->data(0, NameRole).toString();
            const int count = packageCount(item);
            item->setText(0, QString("%1 (%2)").arg(label).arg(count));
            item->setHidden(count == 0);
        }
        for (int index = 0; index < item->childCount(); ++index)
            updatePackageContainerCounts(item->child(index));
    }

    QString packageContainerKey(const QStringList& owners) const
    {
        if (owners.size() == 1) return owners.constFirst();
        const QString prefix = owners.constFirst().section('.', 0, 0);
        for (const QString& owner : owners)
            if (owner.section('.', 0, 0) != prefix) return "shared";
        return prefix + ".shared";
    }

    QTreeWidgetItem* packageParentForContainer(const QString& containerKey,
                                               const QString& family, bool rootPackage)
    {
        auto* container = m_groups.value(containerKey, m_groups.value("base"));
        const QString typeKey = containerKey + (rootPackage ? "/requirements" : "/dependencies");
        if (!m_packageTypeGroups.contains(typeKey)) {
            auto* typeItem = makeGroup(rootPackage ? "Требования ISO"
                                                   : "Зависимости пакетов (pacman)",
                                       container);
            typeItem->setExpanded(true);
            m_packageTypeGroups.insert(typeKey, typeItem);
        }
        auto* typeItem = m_packageTypeGroups.value(typeKey);
        const QString familyKey = typeKey + '/' + family;
        if (!m_familyGroups.contains(familyKey)) {
            auto* familyItem = makeGroup(familyDisplayName(family), typeItem);
            familyItem->setExpanded(true);
            m_familyGroups.insert(familyKey, familyItem);
        }
        return m_familyGroups.value(familyKey);
    }

    QTreeWidgetItem* packageParent(const QStringList& owners, const QString& family,
                                   bool rootPackage)
    {
        return packageParentForContainer(packageContainerKey(owners), family, rootPackage);
    }

    QString sharedPackageLocation(const QString& containerKey) const
    {
        return containerKey == "shared" ? "Общие пакеты компонентов"
                                         : "Общие пакеты частей";
    }

    void addPackage(const QString& package, bool explicitPackage)
    {
        if (m_packageItems.contains(package)) return;
        const QStringList owners = ownersForPackage(package, m_ownerRules);
        const QString family = familyForPackage(package, m_familyRules);
        auto* parent = packageParent(owners, family, explicitPackage);
        auto* item = new QTreeWidgetItem(parent);
        item->setText(0, packageDisplayName(package));
        item->setData(0, KindRole, "package");
        item->setData(0, NameRole, package);
        item->setData(0, OwnersRole, owners);
        item->setData(0, RootPackageRole, explicitPackage);
        item->setCheckState(0, Qt::Unchecked);
        item->setText(1, ownersDisplayText(owners));
        item->setText(2, "—");
        item->setText(3, "не проверялась");
        item->setText(4, explicitPackage ? "требуется; не скачан"
                                         : "зависимость; не скачана");
        m_packageItems.insert(package, item);
        auto* check = new QPushButton("Проверить");
        auto* download = new QPushButton("Скачать");
        m_packageDownloadButtons.insert(package, download);
        m_tree->setItemWidget(item, 5, check);
        m_tree->setItemWidget(item, 6, download);
        connect(check, &QPushButton::clicked, this, [this, package] { checkPackages({package}); });
        connect(download, &QPushButton::clicked, this, [this, package] { downloadPackages({package}); });

        const QString containerKey = packageContainerKey(owners);
        if (owners.size() > 1) {
            const QString location = sharedPackageLocation(containerKey);
            for (const QString& owner : owners) {
                auto* referenceParent = packageParentForContainer(owner, family, explicitPackage);
                auto* reference = new QTreeWidgetItem(referenceParent);
                reference->setText(0, packageDisplayName(package));
                reference->setData(0, KindRole, "package-reference");
                reference->setData(0, NameRole, package);
                reference->setData(0, OwnersRole, owners);
                reference->setData(0, RootPackageRole, explicitPackage);
                reference->setText(1, ownersDisplayText(owners));
                reference->setText(4, QString("общий пакет; управление в разделе «%1»").arg(location));
                m_packageReferences.insert(package, reference);
            }
        }
    }

    int packageCount(QTreeWidgetItem* item) const
    {
        const QString kind = item->data(0, KindRole).toString();
        const bool externalPackage = kind == "component"
            && item->data(0, NameRole).toString() == "sing-box";
        int count = kind == "package" || kind == "package-reference" || externalPackage ? 1 : 0;
        for (int index = 0; index < item->childCount(); ++index)
            count += packageCount(item->child(index));
        return count;
    }

    void finishTreeLayout(QTreeWidgetItem* iso)
    {
        m_tree->collapseAll();
        iso->setExpanded(true);
        QList<QTreeWidgetItem*> pending{iso};
        while (!pending.isEmpty()) {
            auto* parent = pending.takeFirst();
            for (int index = 0; index < parent->childCount(); ++index) {
                auto* child = parent->child(index);
                if (child->data(0, PackageContainerRole).toBool()) {
                    const QString label = child->data(0, NameRole).toString();
                    const int count = packageCount(child);
                    child->setText(0, QString("%1 (%2)").arg(label).arg(count));
                    child->setHidden(count == 0);
                    expandGroupDescendants(child);
                    child->setExpanded(false);
                } else if (child->childCount() > 0) {
                    child->setExpanded(true);
                    pending.append(child);
                }
            }
        }
    }

    void populateTree()
    {
        m_tree->clear();
        m_groups.clear();
        m_packageTypeGroups.clear();
        m_familyGroups.clear();
        m_packageItems.clear();
        m_packageReferences.clear();
        m_packageDownloadButtons.clear();
        m_componentItems.clear();
        m_buildableItems.clear();
        auto* iso = makeGroup("KaskadOS ISO");
        auto* components = makeGroup("Компоненты", iso);

        auto* installer = makeGroup("Установщик", components);
        auto* installerSources = makeGroup("Собираемые части", installer);
        auto* calamares = addComponent(installerSources, "Calamares", "components/calamares",
                                      "build/calamares/calamares", "calamares");
        makePackageContainer("installer.calamares", "Пакеты ISO", calamares);
        auto* installerCompositor = addComponent(
            installerSources, "Композитор установщика", "components/kaskad-desktop/compositor",
            "build/kaskad-installer-compositor/bin/kaskad-installer", "installer-compositor");
        makePackageContainer("installer.compositor", "Пакеты ISO", installerCompositor);
        makePackageContainer("installer.shared", "Общие пакеты частей", installer);

        auto* desktop = makeGroup("Kaskad DE", components);
        auto* desktopSources = makeGroup("Собираемые части", desktop);
        auto* compositor = addComponent(desktopSources, "Композитор", "components/kaskad-desktop/compositor",
                                        "build/kaskad-desktop/compositor/bin/kaskad-compositor", "kaskad-compositor");
        makePackageContainer("desktop.compositor", "Пакеты ISO", compositor);
        auto* portal = addComponent(desktopSources, "Портал рабочего стола", "components/kaskad-desktop/portal",
                                    "build/kaskad-desktop/portal/bin/xdg-desktop-portal-kaskad", "kaskad-portal");
        makePackageContainer("desktop.portal", "Пакеты ISO", portal);
        auto* shell = addComponent(desktopSources, "Оболочка", "components/kaskad-desktop/shell",
                                   "build/kaskad-desktop/shell-source/core/bin/kaskad-shell", "kaskad-shell");
        makePackageContainer("desktop.shell", "Пакеты ISO", shell);
        auto* integration = makeGroup("Интеграция системы", desktop);
        makePackageContainer("desktop.integration", "Пакеты ISO", integration);
        makePackageContainer("desktop.shared", "Общие пакеты частей", desktop);

        auto* regalia = makeGroup("Regalia VPN", components);
        auto* regaliaSources = makeGroup("Собираемые части", regalia);
        auto* regaliaPackages = makePackageContainer("regalia", "Пакеты ISO", regalia);
        addComponent(regaliaSources, "Клиент и системные службы", "components/regalia",
                     "build/regalia/bin/regalia", "regalia");
        const QString singBoxVersion = readAssignment(
            m_projectDirectory + "/components/regalia/packaging/sing-box.env", "SING_BOX_VERSION");
        addComponent(regaliaPackages, "sing-box", "components/regalia",
                     "build/regalia/bin/sing-box", "sing-box", singBoxVersion, true);

        auto* bootloaders = makeGroup("Загрузчики устанавливаемой системы", components);
        makePackageContainer("bootloaders", "Пакеты ISO", bootloaders);
        auto* graphics = makeGroup("Графика и драйверы", components);
        makePackageContainer("graphics", "Пакеты ISO", graphics);
        auto* network = makeGroup("Сетевое окружение", components);
        makePackageContainer("network", "Пакеты ISO", network);
        auto* storage = makeGroup("Диски и файловые системы", components);
        makePackageContainer("storage", "Пакеты ISO", storage);
        auto* base = makeGroup("Базовая Live-система", components);
        makePackageContainer("base", "Пакеты ISO", base);
        makePackageContainer("shared", "Общие пакеты компонентов", iso);

        const QString preparedPackages = m_projectDirectory + "/build/iso-profile/packages.x86_64";
        const bool preparedProfile = QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready");
        const QString packageList = preparedProfile && QFileInfo::exists(preparedPackages)
            ? preparedPackages : m_projectDirectory + "/profile/packages.x86_64";
        for (const QString& package : readPackageList(packageList))
            addPackage(package, true);
        const auto resolvedPackages = readResolvedPackages(
            m_projectDirectory + "/build/iso-resolved-packages.tsv");
        QStringList resolvedNames = resolvedPackages.keys();
        resolvedNames.sort(Qt::CaseInsensitive);
        for (const QString& package : std::as_const(resolvedNames)) {
            addPackage(package, false);
            m_packageItems.value(package)->setText(3, resolvedPackages.value(package));
        }
        finishTreeLayout(iso);
    }

    QStringList selectedComponents() const
    {
        QStringList result;
        for (auto iterator = m_buildableItems.cbegin(); iterator != m_buildableItems.cend(); ++iterator)
            if (iterator.value()->checkState(0) == Qt::Checked) result.append(iterator.key());
        result.sort(Qt::CaseInsensitive);
        return result;
    }

    QStringList selectedPackages() const
    {
        QStringList result;
        for (auto iterator = m_packageItems.cbegin(); iterator != m_packageItems.cend(); ++iterator)
            if (iterator.value()->checkState(0) == Qt::Checked) result.append(iterator.key());
        result.sort(Qt::CaseInsensitive);
        return result;
    }

    void refreshLocalState()
    {
        populateTree();
        QStringList archives;
        for (const QString& path : {m_projectDirectory + "/build/package-cache",
                                    m_projectDirectory + "/build/repository-bootstrap/x86_64"}) {
            QDir directory(path);
            for (const QFileInfo& file : directory.entryInfoList(
                     {"*.pkg.tar.zst", "*.pkg.tar.xz"}, QDir::Files))
                archives.append(file.absoluteFilePath());
        }
        if (!archives.isEmpty()) {
            QProcess query;
            QStringList arguments = {"-Qp"};
            arguments.append(archives);
            query.start("pacman", arguments);
            if (query.waitForFinished(30000)) {
                for (const QString& line : QString::fromUtf8(query.readAllStandardOutput())
                         .split('\n', Qt::SkipEmptyParts)) {
                    const QStringList fields = line.simplified().split(' ');
                    if (fields.size() < 2) continue;
                    if (!m_packageItems.contains(fields.at(0))) continue;
                    auto* item = m_packageItems.value(fields.at(0));
                    item->setText(2, fields.at(1));
                    item->setData(0, LocalVersionRole, fields.at(1));
                    item->setText(4, item->data(0, RootPackageRole).toBool()
                                         ? "требуется; есть локально"
                                         : "зависимость; есть локально");
                    if (m_packageDownloadButtons.contains(fields.at(0)))
                        m_packageDownloadButtons.value(fields.at(0))->setText("Скачать заново");
                }
            }
        }
        const bool profileReady = QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready");
        const bool ready = profileReady
            && QFileInfo::exists(m_projectDirectory + "/build/iso-offline.ready")
            && QFileInfo(m_projectDirectory + "/build/iso-resolved-packages.tsv").size() > 0;
        m_buildIso->setEnabled(ready && !m_process);
        m_buildIso->setToolTip(ready ? QString()
            : !profileReady ? "Сначала упакуйте готовые компоненты в профиль ISO."
                            : "Сначала подготовьте полный локальный кэш.");
        auto* iso = m_tree->topLevelItem(0);
        if (iso) finishTreeLayout(iso);
    }

    void checkPackages(const QStringList& packages)
    {
        if (!QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready")) {
            QMessageBox::information(this, "Профиль не подготовлен",
                                     "Сначала упакуйте готовые компоненты в профиль ISO.");
            return;
        }
        QStringList arguments = {m_projectDirectory + "/scripts/check-iso-packages.sh"};
        arguments.append(packages);
        runCommand(packages.isEmpty() ? "Проверка всех пакетов" : "Проверка выбранных пакетов",
                   "bash", arguments, false, true);
    }

    void downloadPackages(const QStringList& packages)
    {
        if (packages.isEmpty()) {
            QMessageBox::information(this, "Ничего не выбрано", "Отметьте хотя бы один пакет.");
            return;
        }
        if (!QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready")) {
            QMessageBox::information(this, "Профиль не подготовлен",
                                     "Сначала упакуйте готовые компоненты в профиль ISO.");
            return;
        }
        QStringList arguments = {m_projectDirectory + "/scripts/cache-iso-packages.sh"};
        arguments.append(packages);
        runCommand("Загрузка выбранных пакетов", "bash", arguments, true);
    }

    void downloadAllPackages()
    {
        if (!QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready")) {
            QMessageBox::information(this, "Профиль не подготовлен",
                                     "Сначала упакуйте готовые компоненты в профиль ISO.");
            return;
        }
        runCommand("Загрузка всех пакетов ISO", "bash",
                   {m_projectDirectory + "/scripts/cache-iso-packages.sh"}, true);
    }

    void buildIso()
    {
        if (!QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready")
            || !QFileInfo::exists(m_projectDirectory + "/build/iso-offline.ready")
            || QFileInfo(m_projectDirectory + "/build/iso-resolved-packages.tsv").size() <= 0) {
            QMessageBox::critical(this, "Кэш не готов",
                                  "ISO не будет собран: профиль или полный локальный кэш не готовы.");
            return;
        }
        runCommand("Офлайн-сборка ISO", "make", {"iso"}, true, false, true);
    }

    void runCommand(const QString& title, const QString& program, const QStringList& arguments,
                    bool refreshAfter, bool parseVersions = false, bool usePkexec = false)
    {
        if (m_process) {
            QMessageBox::information(this, "Команда уже выполняется",
                                     "Сначала дождитесь завершения текущей команды.");
            return;
        }
        m_versionBuffer.clear();
        m_log->clear();
        m_log->appendPlainText(title + "\n$ " + program + ' ' + arguments.join(' ') + "\n");
        m_progress->setRange(0, 0);
        setBusy(true);
        m_process = new QProcess(this);
        m_process->setWorkingDirectory(m_projectDirectory);
        m_process->setProcessChannelMode(QProcess::MergedChannels);
        if (usePkexec) {
            auto environment = QProcessEnvironment::systemEnvironment();
            environment.insert("KASKADOS_PRIVILEGE_HELPER", "pkexec");
            m_process->setProcessEnvironment(environment);
        }
        connect(m_process, &QProcess::readyReadStandardOutput, this, [this, parseVersions] {
            const QString text = QString::fromUtf8(m_process->readAllStandardOutput());
            m_log->moveCursor(QTextCursor::End);
            m_log->insertPlainText(text);
            if (parseVersions) parseVersionOutput(text);
        });
        connect(m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
                [this, refreshAfter, parseVersions](int exitCode, QProcess::ExitStatus status) {
            m_log->appendPlainText("\nЗавершено, код: " + QString::number(exitCode));
            const bool success = status == QProcess::NormalExit && exitCode == 0;
            m_progress->setRange(0, 1);
            m_progress->setValue(success ? 1 : 0);
            m_process->deleteLater();
            m_process = nullptr;
            setBusy(false);
            if (refreshAfter) refreshLocalState();
            if (!success && !parseVersions)
                QMessageBox::critical(this, "Команда завершилась с ошибкой",
                                      "Подробности показаны в журнале.");
        });
        m_process->start(program, arguments);
    }

    void parseVersionOutput(const QString& text)
    {
        m_versionBuffer += text;
        qsizetype newline;
        while ((newline = m_versionBuffer.indexOf('\n')) >= 0) {
            const QString line = m_versionBuffer.left(newline).trimmed();
            m_versionBuffer.remove(0, newline + 1);
            const QStringList fields = line.split('\t');
            if (line.startsWith("@@COMPONENT@@\t")) {
                if (fields.size() < 4 || !m_componentItems.contains(fields.at(1))) continue;
                auto* item = m_componentItems.value(fields.at(1));
                const QString current = fields.at(2);
                const QString available = fields.at(3);
                item->setText(2, current);
                item->setText(3, available);
                item->setText(4, current == available ? "актуален" : "доступно обновление");
                continue;
            }
            if (!line.startsWith("@@PACKAGE@@\t") || fields.size() < 3) continue;
            const QString package = fields.at(1);
            const QString version = fields.at(2);
            if (!m_packageItems.contains(package))
                addPackage(package, false);
            auto* item = m_packageItems.value(package);
            item->setText(3, version);
            const QString local = item->data(0, LocalVersionRole).toString();
            const QString type = item->data(0, RootPackageRole).toBool()
                ? "требуется" : "зависимость";
            item->setText(4, local.isEmpty() ? type + "; не скачан"
                                            : local == version ? type + "; актуален"
                                                               : type + "; доступно обновление");
            if (m_packageDownloadButtons.contains(package))
                m_packageDownloadButtons.value(package)->setText(
                    local.isEmpty() ? "Скачать"
                                    : local == version ? "Скачать заново" : "Обновить");
        }
        if (auto* iso = m_tree->topLevelItem(0)) updatePackageContainerCounts(iso);
    }

    void setBusy(bool busy)
    {
        m_stop->setEnabled(busy);
        m_buildSelected->setEnabled(!busy);
        m_packageProfile->setEnabled(!busy);
        m_tree->setEnabled(!busy);
        m_buildIso->setEnabled(!busy
            && QFileInfo::exists(m_projectDirectory + "/build/iso-profile.ready")
            && QFileInfo::exists(m_projectDirectory + "/build/iso-offline.ready")
            && QFileInfo(m_projectDirectory + "/build/iso-resolved-packages.tsv").size() > 0);
    }

    QString m_projectDirectory;
    OwnerRules m_ownerRules;
    OwnerRules m_familyRules;
    QStackedWidget* m_pages = nullptr;
    QWidget* m_buildPage = nullptr;
    QTreeWidget* m_tree = nullptr;
    QPlainTextEdit* m_log = nullptr;
    QProgressBar* m_progress = nullptr;
    QPushButton* m_buildSelected = nullptr;
    QPushButton* m_packageProfile = nullptr;
    QPushButton* m_buildIso = nullptr;
    QPushButton* m_stop = nullptr;
    QProcess* m_process = nullptr;
    QHash<QString, QTreeWidgetItem*> m_groups;
    QHash<QString, QTreeWidgetItem*> m_packageTypeGroups;
    QHash<QString, QTreeWidgetItem*> m_familyGroups;
    QHash<QString, QTreeWidgetItem*> m_packageItems;
    QMultiHash<QString, QTreeWidgetItem*> m_packageReferences;
    QHash<QString, QPushButton*> m_packageDownloadButtons;
    QHash<QString, QTreeWidgetItem*> m_componentItems;
    QHash<QString, QTreeWidgetItem*> m_buildableItems;
    QString m_versionBuffer;
};

int main(int argc, char* argv[])
{
    QApplication application(argc, argv);
    QCoreApplication::setApplicationName("kaskados-manager");
    QCommandLineParser parser;
    parser.addHelpOption();
    QCommandLineOption projectOption({"p", "project"}, "Каталог проекта KaskadOS", "path",
                                     inferProjectDirectory());
    parser.addOption(projectOption);
    parser.process(application);
    const QString project = QDir(parser.value(projectOption)).absolutePath();
    if (!QFileInfo::exists(project + "/profile/packages.x86_64")) {
        QMessageBox::critical(nullptr, "KaskadOS Manager", "Не найден проект KaskadOS: " + project);
        return 2;
    }
    ManagerWindow window(project);
    window.show();
    return application.exec();
}
