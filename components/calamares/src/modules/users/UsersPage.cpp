/* === This file is part of Calamares - <https://calamares.io> ===
 *
 *   SPDX-FileCopyrightText: 2014-2017 Teo Mrnjavac <teo@kde.org>
 *   SPDX-FileCopyrightText: 2017-2018 Adriaan de Groot <groot@kde.org>
 *   SPDX-FileCopyrightText: 2019 Collabora Ltd <arnaud.ferraris@collabora.com>
 *   SPDX-FileCopyrightText: 2020 Gabriel Craciunescu <crazy@frugalware.org>
 *   SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   Portions from the Manjaro Installation Framework
 *   by Roland Singer <roland@manjaro.org>
 *   Copyright (C) 2007 Free Software Foundation, Inc.
 *
 *   Calamares is Free Software: see the License-Identifier above.
 *
 */

#include "UsersPage.h"

#include "Config.h"
#include "ui_page_usersetup.h"

#include "GlobalStorage.h"
#include "JobQueue.h"
#include "Settings.h"
#include "compat/CheckBox.h"
#include "utils/Gui.h"
#include "utils/Logger.h"
#include "utils/Retranslator.h"
#include "utils/String.h"
#include "ViewManager.h"

#include <QBoxLayout>
#include <QComboBox>
#include <QDir>
#include <QFile>
#include <QFrame>
#include <QGridLayout>
#include <QIcon>
#include <QLabel>
#include <QLineEdit>
#include <QPainter>
#include <QPixmap>
#include <QPushButton>
#include <QResizeEvent>

namespace
{
QIcon
materialIcon( const QString& glyph, const QColor& color, int pixelSize = 22 )
{
    const int canvasSize = pixelSize + 8;
    QPixmap pixmap( canvasSize, canvasSize );
    pixmap.fill( Qt::transparent );

    QPainter painter( &pixmap );
    painter.setRenderHint( QPainter::Antialiasing );
    painter.setPen( color );
    QFont font( QStringLiteral( "Material Symbols Rounded" ) );
    font.setStyleName( QStringLiteral( "Medium" ) );
    font.setPixelSize( pixelSize );
    font.setWeight( QFont::Medium );
    painter.setFont( font );
    painter.drawText( pixmap.rect(), Qt::AlignCenter, glyph );
    return QIcon( pixmap );
}

void clearLayout( QLayout* layout )
{
    while ( QLayoutItem* item = layout->takeAt( 0 ) )
    {
        if ( item->layout() )
        {
            clearLayout( item->layout() );
        }
        delete item;
    }
}
}

/** @brief Add an error message and pixmap to a label. */
static inline void
labelError( QLabel* pix, QLabel* label, Calamares::ImageType icon, const QString& message )
{
    label->setText( message );
    pix->setPixmap( Calamares::defaultPixmap( icon, Calamares::Original, pix->size() ) );
}

/** @brief Clear error, set happy pixmap on a label to indicate "ok". */
static inline void
labelOk( QLabel* pix, QLabel* label )
{
    label->clear();
    pix->setPixmap( Calamares::defaultPixmap( Calamares::StatusOk, Calamares::Original, pix->size() ) );
}

/** @brief Sets error or ok on a label depending on @p status and @p value
 *
 * - An **empty** @p value gets no message and no icon.
 * - A non-empty @p value, with an **empty** @p status gets an "ok".
 * - A non-empty @p value with a non-empty @p status gets an error indicator.
 */
static inline void
labelStatus( QLabel* pix, QLabel* label, const QString& value, const QString& status )
{
    if ( status.isEmpty() )
    {
        if ( value.isEmpty() )
        {
            // This is different from labelOK() because no checkmark is shown
            label->clear();
            pix->clear();
        }
        else
        {
            labelOk( pix, label );
        }
    }
    else
    {
        labelError( pix, label, Calamares::ImageType::StatusError, status );
    }
}

UsersPage::UsersPage( Config* config, QWidget* parent )
    : QWidget( parent )
    , ui( new Ui::Page_UserSetup )
    , m_config( config )
{
    ui->setupUi( this );

    ui->labelWhatIsYourName->setProperty( "heading", true );
    auto* subtitle = new QLabel( tr( "Основная учётная запись с правами администратора." ), this );
    subtitle->setObjectName( QStringLiteral( "pageSubtitle" ) );
    ui->verticalLayout_12->insertWidget( 2, subtitle );

    auto* sectionTitle = new QLabel( tr( "Данные профиля" ), this );
    sectionTitle->setObjectName( QStringLiteral( "sectionTitle" ) );
    ui->verticalLayout_12->insertWidget( 3, sectionTitle );

    ui->textBoxFullName->setMaximumWidth( 520 );
    ui->textBoxLoginName->setMaximumWidth( 300 );
    ui->textBoxHostname->setMaximumWidth( 300 );
    ui->textBoxUserPassword->setMaximumWidth( 300 );
    ui->textBoxUserVerifiedPassword->setMaximumWidth( 300 );

    // Connect signals and slots
    ui->textBoxUserPassword->setText( config->userPassword() );
    connect( ui->textBoxUserPassword, &QLineEdit::textChanged, config, &Config::setUserPassword );
    connect( config, &Config::userPasswordChanged, ui->textBoxUserPassword, &QLineEdit::setText );
    ui->textBoxUserVerifiedPassword->setText( config->userPasswordSecondary() );
    connect( ui->textBoxUserVerifiedPassword, &QLineEdit::textChanged, config, &Config::setUserPasswordSecondary );
    connect( config, &Config::userPasswordSecondaryChanged, ui->textBoxUserVerifiedPassword, &QLineEdit::setText );
    connect( config, &Config::userPasswordStatusChanged, this, &UsersPage::reportUserPasswordStatus );

    ui->textBoxRootPassword->setText( config->rootPassword() );
    connect( ui->textBoxRootPassword, &QLineEdit::textChanged, config, &Config::setRootPassword );
    connect( config, &Config::rootPasswordChanged, ui->textBoxRootPassword, &QLineEdit::setText );
    ui->textBoxVerifiedRootPassword->setText( config->rootPasswordSecondary() );
    connect( ui->textBoxVerifiedRootPassword, &QLineEdit::textChanged, config, &Config::setRootPasswordSecondary );
    connect( config, &Config::rootPasswordSecondaryChanged, ui->textBoxVerifiedRootPassword, &QLineEdit::setText );
    connect( config, &Config::rootPasswordStatusChanged, this, &UsersPage::reportRootPasswordStatus );

    ui->textBoxFullName->setText( config->fullName() );
    connect( ui->textBoxFullName, &QLineEdit::textEdited, config, &Config::setFullName );
    connect( config, &Config::fullNameChanged, this, &UsersPage::onFullNameTextEdited );

    // If the hostname is going to be written out, then show the field
    if ( ( m_config->hostnameAction() == HostNameAction::EtcHostname )
         || ( m_config->hostnameAction() == HostNameAction::SystemdHostname ) )
    {
        ui->textBoxHostname->setText( config->hostname() );
        connect( ui->textBoxHostname, &QLineEdit::textEdited, config, &Config::setHostName );
        connect( config,
                 &Config::hostnameChanged,
                 [ this ]( const QString& name )
                 {
                     if ( !ui->textBoxHostname->hasFocus() )
                     {
                         ui->textBoxHostname->setText( name );
                     }
                 } );
        connect( config, &Config::hostnameStatusChanged, this, &UsersPage::reportHostNameStatus );
    }
    else
    {
        // Need to hide the hostname parts individually because there's no widget-group
        ui->hostnameLabel->hide();
        ui->labelHostname->hide();
        ui->textBoxHostname->hide();
        ui->labelHostnameError->hide();
    }

    ui->textBoxLoginName->setText( config->loginName() );
    connect( ui->textBoxLoginName, &QLineEdit::textEdited, config, &Config::setLoginName );
    connect( config, &Config::loginNameChanged, ui->textBoxLoginName, &QLineEdit::setText );
    connect( config, &Config::loginNameStatusChanged, this, &UsersPage::reportLoginNameStatus );

    ui->checkBoxDoAutoLogin->setVisible( m_config->displayAutoLogin() );
    ui->checkBoxDoAutoLogin->setChecked( m_config->doAutoLogin() );
    connect( ui->checkBoxDoAutoLogin,
             Calamares::checkBoxStateChangedSignal,
             this,
             [ this ]( Calamares::checkBoxStateType checked )
             { m_config->setAutoLogin( checked != Calamares::checkBoxUncheckedValue ); } );
    connect( config, &Config::autoLoginChanged, ui->checkBoxDoAutoLogin, &QCheckBox::setChecked );

    ui->checkBoxReusePassword->setVisible( m_config->writeRootPassword() );
    ui->checkBoxReusePassword->setChecked( m_config->reuseUserPasswordForRoot() );
    if ( m_config->writeRootPassword() )
    {
        connect( config, &Config::reuseUserPasswordForRootChanged, ui->checkBoxReusePassword, &QCheckBox::setChecked );
        connect( ui->checkBoxReusePassword, Calamares::checkBoxStateChangedSignal, this, &UsersPage::onReuseUserPasswordChanged );
    }

    ui->checkBoxAllowWeakPassword->setVisible( m_config->permitWeakPasswords() );
    ui->checkBoxAllowWeakPassword->setChecked( !m_config->requireStrongPasswords() );
    if ( m_config->permitWeakPasswords() )
    {
        connect( ui->checkBoxAllowWeakPassword,
                 Calamares::checkBoxStateChangedSignal,
                 this,
                 [ this ]( int checked ) { m_config->setRequireStrongPasswords( checked == Qt::Unchecked ); } );
        connect( config,
                 &Config::requireStrongPasswordsChanged,
                 this,
                 [ this ]( bool strong ) { ui->checkBoxAllowWeakPassword->setChecked( !strong ); } );
    }

    // Active Directory is not checked or enabled by default
    ui->useADCheckbox->setVisible( m_config->getActiveDirectoryEnabled() );
    onActiveDirectoryToggled( false );

    connect( ui->useADCheckbox, &QCheckBox::toggled, this, &UsersPage::onActiveDirectoryToggled );
    connect( ui->domainField, &QLineEdit::textChanged, config, &Config::setActiveDirectoryDomain );
    connect( ui->domainAdminField, &QLineEdit::textChanged, config, &Config::setActiveDirectoryAdminUsername );
    connect( ui->domainPasswordField, &QLineEdit::textChanged, config, &Config::setActiveDirectoryAdminPassword );
    connect( ui->ipAddressField, &QLineEdit::textChanged, config, &Config::setActiveDirectoryIP );

    CALAMARES_RETRANSLATE_SLOT( &UsersPage::retranslate );

    onReuseUserPasswordChanged( m_config->reuseUserPasswordForRoot() );
    onFullNameTextEdited( m_config->fullName() );
    reportLoginNameStatus( m_config->loginNameStatus() );
    reportHostNameStatus( m_config->hostnameStatus() );

    ui->textBoxLoginName->setEnabled( m_config->isEditable( "loginName" ) );
    ui->textBoxFullName->setEnabled( m_config->isEditable( "fullName" ) );

    retranslate();
    buildKaskadStartPage();
}

void
UsersPage::buildKaskadStartPage()
{
    const auto widgets = findChildren< QWidget* >();
    for ( QWidget* widget : widgets )
    {
        widget->hide();
    }
    clearLayout( ui->verticalLayout_12 );
    ui->verticalLayout_12->setContentsMargins( 0, 0, 0, 0 );
    ui->verticalLayout_12->setSpacing( 0 );

    auto* content = new QWidget( this );
    m_startContent = content;
    content->setObjectName( QStringLiteral( "kaskadStartPage" ) );
    content->setFixedWidth( 1012 );
    auto* columns = new QHBoxLayout( content );
    m_startColumns = columns;
    columns->setContentsMargins( 0, 62, 0, 0 );
    columns->setSpacing( 115 );

    auto* left = new QWidget( content );
    m_startLeft = left;
    left->setObjectName( QStringLiteral( "startLeftColumn" ) );
    left->setFixedWidth( 360 );
    auto* leftLayout = new QVBoxLayout( left );
    leftLayout->setContentsMargins( 0, 0, 0, 0 );
    leftLayout->setSpacing( 0 );

    auto* title = new QLabel( tr( "Установить KaskadOS" ), left );
    title->setObjectName( QStringLiteral( "startPageTitle" ) );
    auto* subtitle = new QLabel( tr( "Введите имя и пароль - остальное уже готово" ), left );
    subtitle->setObjectName( QStringLiteral( "startPageSubtitle" ) );
    leftLayout->addWidget( title );
    leftLayout->addSpacing( 4 );
    leftLayout->addWidget( subtitle );
    leftLayout->addSpacing( 38 );

    auto addChoiceCard = [ left, leftLayout ]( const QString& glyph,
                                               const QString& primary,
                                               const QString& secondary ) -> QPushButton*
    {
        auto* card = new QFrame( left );
        card->setObjectName( QStringLiteral( "startChoiceCard" ) );
        card->setFixedHeight( 72 );
        auto* row = new QHBoxLayout( card );
        row->setContentsMargins( 14, 9, 14, 9 );
        row->setSpacing( 14 );
        auto* badge = new QLabel( card );
        badge->setObjectName( QStringLiteral( "startChoiceIcon" ) );
        badge->setAlignment( Qt::AlignCenter );
        badge->setFixedSize( 42, 42 );
        badge->setPixmap( materialIcon( glyph, QColor( QStringLiteral( "#D8E5DD" ) ), 23 ).pixmap( 30, 30 ) );
        auto* texts = new QWidget( card );
        texts->setObjectName( QStringLiteral( "startChoiceTexts" ) );
        auto* textLayout = new QVBoxLayout( texts );
        textLayout->setContentsMargins( 0, 0, 0, 0 );
        textLayout->setSpacing( 1 );
        auto* first = new QLabel( primary, texts );
        first->setObjectName( QStringLiteral( "startChoicePrimary" ) );
        auto* second = new QLabel( secondary, texts );
        second->setObjectName( QStringLiteral( "startChoiceSecondary" ) );
        textLayout->addWidget( first );
        textLayout->addWidget( second );
        auto* edit = new QPushButton( card );
        edit->setObjectName( QStringLiteral( "startChoiceEdit" ) );
        edit->setFixedSize( 42, 42 );
        edit->setIcon( materialIcon( QStringLiteral( "edit" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ) );
        edit->setIconSize( QSize( 28, 28 ) );
        row->addWidget( badge );
        row->addWidget( texts, 1 );
        row->addWidget( edit );
        leftLayout->addWidget( card );
        leftLayout->addSpacing( 4 );
        return edit;
    };
    auto* languageEdit = addChoiceCard( QStringLiteral( "language" ),
                                        tr( "Русский" ),
                                        tr( "Москва · UTC+3" ) );
    auto* keyboardEdit = addChoiceCard( QStringLiteral( "keyboard" ),
                                        tr( "Русская + English (US)" ),
                                        tr( "Alt + Shift" ) );
    connect( languageEdit, &QPushButton::clicked, this, [] {
        Calamares::ViewManager::instance()->goToStep( QStringLiteral( "locale" ) );
    } );
    connect( keyboardEdit, &QPushButton::clicked, this, [] {
        Calamares::ViewManager::instance()->goToStep( QStringLiteral( "keyboard" ) );
    } );
    leftLayout->addStretch();

    auto* right = new QWidget( content );
    right->setObjectName( QStringLiteral( "startRightColumn" ) );
    auto* rightLayout = new QVBoxLayout( right );
    rightLayout->setContentsMargins( 0, 0, 0, 0 );
    rightLayout->setSpacing( 0 );

    auto* accountTitle = new QLabel( tr( "Учётная запись" ), right );
    accountTitle->setObjectName( QStringLiteral( "startSectionTitle" ) );
    rightLayout->addWidget( accountTitle );
    rightLayout->addSpacing( 14 );

    auto field = [ right ]( const QString& label, QLineEdit* edit )
    {
        auto* box = new QWidget( right );
        auto* layout = new QVBoxLayout( box );
        layout->setContentsMargins( 0, 0, 0, 0 );
        layout->setSpacing( 4 );
        auto* caption = new QLabel( label, box );
        caption->setObjectName( QStringLiteral( "startFieldLabel" ) );
        edit->setParent( box );
        edit->setObjectName( QStringLiteral( "startField" ) );
        edit->setMinimumHeight( 56 );
        edit->setMaximumWidth( QWIDGETSIZE_MAX );
        edit->show();
        layout->addWidget( caption );
        layout->addWidget( edit );
        box->show();
        return box;
    };

    rightLayout->addWidget( field( tr( "Имя" ), ui->textBoxFullName ) );
    ui->textBoxFullName->addAction(
        materialIcon( QStringLiteral( "person" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ),
        QLineEdit::LeadingPosition );
    auto* example = new QLabel( tr( "Например: Иван" ), right );
    example->setObjectName( QStringLiteral( "startFieldHint" ) );
    rightLayout->addWidget( example );
    rightLayout->addSpacing( 10 );

    auto* identityRow = new QHBoxLayout;
    identityRow->setSpacing( 10 );
    auto* loginBox = field( tr( "Логин" ), ui->textBoxLoginName );
    auto* deviceBox = field( tr( "Имя устройства" ), ui->textBoxHostname );
    m_loginBox = loginBox;
    m_deviceBox = deviceBox;
    ui->textBoxLoginName->addAction(
        materialIcon( QStringLiteral( "badge" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ),
        QLineEdit::LeadingPosition );
    ui->textBoxHostname->addAction(
        materialIcon( QStringLiteral( "computer" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ),
        QLineEdit::LeadingPosition );
    identityRow->addWidget( loginBox, 1 );
    identityRow->addWidget( deviceBox, 1 );
    rightLayout->addLayout( identityRow );
    auto* identityHints = new QHBoxLayout;
    identityHints->setSpacing( 10 );
    m_loginHint = new QLabel( right );
    m_deviceHint = new QLabel( right );
    m_loginHint->setObjectName( QStringLiteral( "startFieldHint" ) );
    m_deviceHint->setObjectName( QStringLiteral( "startFieldHint" ) );
    identityHints->addWidget( m_loginHint, 1 );
    identityHints->addWidget( m_deviceHint, 1 );
    rightLayout->addLayout( identityHints );
    rightLayout->addSpacing( 10 );

    auto* passwordRow = new QHBoxLayout;
    passwordRow->setSpacing( 10 );
    passwordRow->addWidget( field( tr( "Пароль" ), ui->textBoxUserPassword ), 1 );
    passwordRow->addWidget( field( tr( "Повторите пароль" ), ui->textBoxUserVerifiedPassword ), 1 );
    ui->textBoxUserPassword->addAction(
        materialIcon( QStringLiteral( "lock" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ),
        QLineEdit::LeadingPosition );
    ui->textBoxUserVerifiedPassword->addAction(
        materialIcon( QStringLiteral( "lock" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ),
        QLineEdit::LeadingPosition );
    rightLayout->addLayout( passwordRow );
    rightLayout->addSpacing( 18 );

    auto* diskTitle = new QLabel( tr( "Куда установить" ), right );
    diskTitle->setObjectName( QStringLiteral( "startSectionTitle" ) );
    rightLayout->addWidget( diskTitle );
    m_diskCombo = new QComboBox( right );
    m_diskCombo->setObjectName( QStringLiteral( "startDiskCombo" ) );
    m_diskCombo->setMinimumHeight( 56 );
    const QDir sysBlock( QStringLiteral( "/sys/block" ) );
    const QStringList devices = sysBlock.entryList( QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name );
    for ( const QString& device : devices )
    {
        if ( device.startsWith( QLatin1String( "loop" ) ) || device.startsWith( QLatin1String( "ram" ) )
             || device.startsWith( QLatin1String( "zram" ) ) )
        {
            continue;
        }
        QFile modelFile( sysBlock.filePath( device + QStringLiteral( "/device/model" ) ) );
        QString model = device;
        if ( modelFile.open( QIODevice::ReadOnly | QIODevice::Text ) )
        {
            const QString detected = QString::fromUtf8( modelFile.readAll() ).trimmed();
            if ( !detected.isEmpty() ) model = detected;
        }
        QFile sizeFile( sysBlock.filePath( device + QStringLiteral( "/size" ) ) );
        quint64 bytes = 0;
        if ( sizeFile.open( QIODevice::ReadOnly | QIODevice::Text ) )
        {
            bytes = QString::fromUtf8( sizeFile.readAll() ).trimmed().toULongLong() * 512ULL;
        }
        m_diskCombo->addItem( materialIcon( QStringLiteral( "hard_drive" ), QColor( QStringLiteral( "#C8D4CC" ) ), 22 ),
                              tr( "%1 · %2 ГБ" ).arg( model ).arg( bytes / 1000000000ULL ),
                              QStringLiteral( "/dev/%1" ).arg( device ) );
    }
    if ( m_diskCombo->count() == 0 )
    {
        m_diskCombo->addItem( tr( "Накопитель не найден" ) );
        m_diskCombo->setEnabled( false );
    }
    rightLayout->addWidget( m_diskCombo );
    auto* eraseHint = new QLabel( tr( "Готовим диск к новой жизни - всё на выбранном диске будет удалено" ), right );
    eraseHint->setObjectName( QStringLiteral( "startEraseHint" ) );
    rightLayout->addWidget( eraseHint );
    rightLayout->addSpacing( 58 );

    auto* actions = new QHBoxLayout;
    actions->setSpacing( 4 );
    auto* advancedButton = new QPushButton( tr( "Настроить установку" ), right );
    advancedButton->setObjectName( QStringLiteral( "startAdvancedButton" ) );
    advancedButton->setMinimumHeight( 56 );
    advancedButton->setIcon(
        materialIcon( QStringLiteral( "tune" ), QColor( QStringLiteral( "#9BD9B4" ) ), 22 ) );
    advancedButton->setIconSize( QSize( 28, 28 ) );
    auto* installButton = new QPushButton( tr( "Установить KaskadOS" ), right );
    installButton->setObjectName( QStringLiteral( "startInstallButton" ) );
    installButton->setMinimumHeight( 56 );
    installButton->setIcon(
        materialIcon( QStringLiteral( "arrow_forward" ), QColor( QStringLiteral( "#113422" ) ), 22 ) );
    installButton->setIconSize( QSize( 28, 28 ) );
    actions->addWidget( advancedButton, 1 );
    actions->addWidget( installButton, 1 );
    rightLayout->addLayout( actions );
    rightLayout->addStretch();
    connect( advancedButton, &QPushButton::clicked, this, [] {
        Calamares::ViewManager::instance()->goToStep( QStringLiteral( "partition" ) );
    } );
    auto updateInstallEnabled = [ this, installButton ]( bool accountReady ) {
        const bool diskReady = m_diskCombo && m_diskCombo->isEnabled()
            && !m_diskCombo->currentData().toString().isEmpty();
        installButton->setEnabled( accountReady && diskReady );
    };
    connect( m_config, &Config::readyChanged, installButton, updateInstallEnabled );
    updateInstallEnabled( m_config->isReady() );
    connect( installButton, &QPushButton::clicked, this, [ this ] {
        const QString deviceNode = m_diskCombo ? m_diskCombo->currentData().toString() : QString();
        if ( deviceNode.isEmpty() )
        {
            return;
        }
        auto* gs = Calamares::JobQueue::instance()->globalStorage();
        gs->insert( QStringLiteral( "kaskadQuickInstallRequested" ), true );
        gs->insert( QStringLiteral( "kaskadQuickInstallDevice" ), deviceNode );
        Calamares::ViewManager::instance()->goToStep( QStringLiteral( "partition" ) );
    } );

    columns->addWidget( left );
    columns->addWidget( right, 1 );
    ui->verticalLayout_12->addWidget( content, 0, Qt::AlignCenter );

    auto updateHints = [ this ]()
    {
        if ( m_loginHint ) m_loginHint->setText( tr( "%1 · можно изменить" ).arg( ui->textBoxLoginName->text() ) );
        if ( m_deviceHint ) m_deviceHint->setText( tr( "%1 · можно изменить" ).arg( ui->textBoxHostname->text() ) );
    };
    connect( ui->textBoxLoginName, &QLineEdit::textChanged, this, updateHints );
    connect( ui->textBoxHostname, &QLineEdit::textChanged, this, updateHints );
    updateHints();

    content->show();
    left->show();
    right->show();
    title->show();
    subtitle->show();
    accountTitle->show();
    example->show();
    diskTitle->show();
    m_diskCombo->show();
    eraseHint->show();
    m_loginHint->show();
    m_deviceHint->show();
    advancedButton->show();
    installButton->show();
    updateGeneratedFieldsVisibility( !ui->textBoxFullName->text().trimmed().isEmpty() );
    updateStartGeometry();
}

void
UsersPage::resizeEvent( QResizeEvent* event )
{
    QWidget::resizeEvent( event );
    updateStartGeometry();
}

void
UsersPage::updateStartGeometry()
{
    if ( !m_startContent || !m_startLeft || !m_startColumns )
    {
        return;
    }

    const qreal horizontalScale = qMax( 1.0, ( width() - 180 ) / 1012.0 );
    const qreal verticalScale = qMax( 1.0, ( height() - 60 ) / 650.0 );
    const qreal scale = qBound( 1.0, qMin( horizontalScale, verticalScale ), 1.20 );
    const int contentWidth = qRound( 1012 * scale );
    m_startContent->setFixedWidth( contentWidth );
    m_startContent->setFixedHeight( 650 );
    m_startLeft->setFixedWidth( qRound( 360 * scale ) );
    m_startColumns->setSpacing( qRound( 115 * scale ) );
    m_startColumns->setContentsMargins( 0, 62, 0, 0 );
    m_startContent->setStyleSheet( QString() );
}

UsersPage::~UsersPage()
{
    delete ui;
}

void
UsersPage::retranslate()
{
    ui->retranslateUi( this );
    ui->labelWhatIsYourName->setText( tr( "Учётная запись" ) );
    ui->textBoxFullName->setPlaceholderText( tr( "Ваше имя" ) );
    ui->username_label_2->setText( tr( "Имя пользователя" ) );
    ui->textBoxLoginName->setPlaceholderText( tr( "Логин" ) );
    ui->hostnameLabel->setText( tr( "Имя устройства" ) );
    ui->textBoxHostname->setPlaceholderText( tr( "Имя устройства" ) );
    ui->password_label_2->setText( tr( "Пароль" ) );
    ui->textBoxUserPassword->setPlaceholderText( tr( "Пароль" ) );
    ui->textBoxUserVerifiedPassword->setPlaceholderText( tr( "Повторите пароль" ) );
    if ( Calamares::Settings::instance()->isSetupMode() )
    {
        ui->textBoxLoginName->setToolTip( tr( "<small>If more than one person will "
                                              "use this computer, you can create multiple "
                                              "accounts after setup.</small>" ) );
    }
    else
    {
        ui->textBoxLoginName->setToolTip( tr( "<small>If more than one person will "
                                              "use this computer, you can create multiple "
                                              "accounts after installation.</small>" ) );
    }

    const auto up = m_config->userPasswordStatus();
    reportUserPasswordStatus( up.first, up.second );
    const auto rp = m_config->rootPasswordStatus();
    reportRootPasswordStatus( rp.first, rp.second );
}

void
UsersPage::onActivate()
{
    ui->textBoxFullName->setFocus();
    const auto up = m_config->userPasswordStatus();
    reportUserPasswordStatus( up.first, up.second );
    const auto rp = m_config->rootPasswordStatus();
    reportRootPasswordStatus( rp.first, rp.second );
}

void
UsersPage::onFullNameTextEdited( const QString& fullName )
{
    if ( !m_startContent )
    {
        labelStatus( ui->labelFullName, ui->labelFullNameError, fullName, QString() );
    }
    updateGeneratedFieldsVisibility( !fullName.trimmed().isEmpty() );
}

void
UsersPage::updateGeneratedFieldsVisibility( bool visible )
{
    const bool showHostname = visible
        && ( ( m_config->hostnameAction() == HostNameAction::EtcHostname )
             || ( m_config->hostnameAction() == HostNameAction::SystemdHostname ) );

    // These labels belong to the original Calamares form. The Kaskad start page
    // reuses only its line edits, so making the old labels visible would leave
    // them unmanaged at the top-left corner of the page.
    const bool showLegacyLabels = !m_startContent;
    ui->username_label_2->setVisible( showLegacyLabels && visible );
    ui->labelUsername->setVisible( showLegacyLabels && visible );
    ui->labelUsernameError->setVisible( showLegacyLabels && visible );
    ui->hostnameLabel->setVisible( showLegacyLabels && showHostname );
    ui->labelHostname->setVisible( showLegacyLabels && showHostname );
    ui->labelHostnameError->setVisible( showLegacyLabels && showHostname );

    ui->textBoxLoginName->setVisible( visible );
    ui->textBoxHostname->setVisible( showHostname );

    if ( m_loginBox )
    {
        m_loginBox->setVisible( visible );
    }
    if ( m_loginHint )
    {
        m_loginHint->setVisible( visible );
    }
    if ( m_deviceBox )
    {
        m_deviceBox->setVisible( showHostname );
    }
    if ( m_deviceHint )
    {
        m_deviceHint->setVisible( showHostname );
    }
}

void
UsersPage::reportLoginNameStatus( const QString& status )
{
    if ( !m_startContent )
    {
        labelStatus( ui->labelUsername, ui->labelUsernameError, m_config->loginName(), status );
    }
}

void
UsersPage::reportHostNameStatus( const QString& status )
{
    if ( !m_startContent )
    {
        labelStatus( ui->labelHostname, ui->labelHostnameError, m_config->hostname(), status );
    }
}

static inline void
passwordStatus( QLabel* iconLabel, QLabel* messageLabel, int validity, const QString& message )
{
    switch ( validity )
    {
    case Config::PasswordValidity::Valid:
        labelOk( iconLabel, messageLabel );
        break;
    case Config::PasswordValidity::Weak:
        labelError( iconLabel, messageLabel, Calamares::StatusWarning, message );
        break;
    case Config::PasswordValidity::Invalid:
    default:
        labelError( iconLabel, messageLabel, Calamares::StatusError, message );
        break;
    }
}

void
UsersPage::reportRootPasswordStatus( int validity, const QString& message )
{
    if ( !m_startContent )
    {
        passwordStatus( ui->labelRootPassword, ui->labelRootPasswordError, validity, message );
    }
}

void
UsersPage::reportUserPasswordStatus( int validity, const QString& message )
{
    if ( !m_startContent )
    {
        passwordStatus( ui->labelUserPassword, ui->labelUserPasswordError, validity, message );
    }
}

void
UsersPage::onReuseUserPasswordChanged( const int checked )
{
    // Pass the change on to config
    m_config->setReuseUserPasswordForRoot( checked != Qt::Unchecked );
    /* When "reuse" is checked, hide the fields for explicitly
     * entering the root password. However, if we're going to
     * disable the root password anyway, hide them all regardless of
     * the checkbox -- so when writeRoot is false, visible needs
     * to be false, to hide them all.
     *
     * In principle this is only connected when writeRootPassword is @c true,
     * but it is **always** called at least once in the constructor
     * to set up initial visibility.
     */
    const bool visible = m_config->writeRootPassword() ? !checked : false;
    ui->labelChooseRootPassword->setVisible( visible );
    ui->labelRootPassword->setVisible( visible );
    ui->labelRootPasswordError->setVisible( visible );
    ui->textBoxRootPassword->setVisible( visible );
    ui->textBoxVerifiedRootPassword->setVisible( visible );
}

void
UsersPage::onActiveDirectoryToggled( bool checked )
{
    ui->domainLabel->setVisible( checked );
    ui->domainField->setVisible( checked );
    ui->domainAdminLabel->setVisible( checked );
    ui->domainAdminField->setVisible( checked );
    ui->domainPasswordField->setVisible( checked );
    ui->domainPasswordLabel->setVisible( checked );
    ui->ipAddressField->setVisible( checked );
    ui->ipAddressLabel->setVisible( checked );

    m_config->setActiveDirectoryUsed( checked );
}
