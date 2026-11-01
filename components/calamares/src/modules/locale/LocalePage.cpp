/* === This file is part of Calamares - <https://calamares.io> ===
 *
 *   SPDX-FileCopyrightText: 2014-2016 Teo Mrnjavac <teo@kde.org>
 *   SPDX-FileCopyrightText: 2017-2019 Adriaan de Groot <groot@kde.org>
 *   SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   Calamares is Free Software: see the License-Identifier above.
 *
 */

#include "LocalePage.h"

#include "Config.h"
#include "LCLocaleDialog.h"
#include "timezonewidget/timezonewidget.h"

#include "utils/Gui.h"
#include "utils/Logger.h"
#include "utils/RAII.h"
#include "utils/Retranslator.h"
#include "ViewManager.h"

#include <QBoxLayout>
#include <QComboBox>
#include <QFrame>
#include <QLabel>
#include <QLineEdit>
#include <QPointer>
#include <QPushButton>

LocalePage::LocalePage( Config* config, QWidget* parent )
    : QWidget( parent )
    , m_config( config )
    , m_blockTzWidgetSet( false )
{
    auto* pageLayout = new QHBoxLayout( this );
    pageLayout->setContentsMargins( 40, 22, 40, 22 );
    auto* content = new QWidget( this );
    content->setObjectName( QStringLiteral( "kaskadFormPage" ) );
    content->setMinimumWidth( 860 );
    content->setMaximumWidth( 1040 );
    auto* mainLayout = new QVBoxLayout( content );
    mainLayout->setContentsMargins( 0, 0, 0, 0 );
    mainLayout->setSpacing( 0 );
    pageLayout->addStretch();
    pageLayout->addWidget( content, 1 );
    pageLayout->addStretch();

    auto* title = new QLabel( tr( "Язык и регион" ), content );
    title->setObjectName( QStringLiteral( "formPageTitle" ) );
    auto* subtitle = new QLabel( tr( "Измените только язык и часовой пояс." ), content );
    subtitle->setObjectName( QStringLiteral( "formPageSubtitle" ) );
    mainLayout->addWidget( title );
    mainLayout->addSpacing( 5 );
    mainLayout->addWidget( subtitle );
    mainLayout->addSpacing( 34 );

    auto* search = new QLineEdit( content );
    search->setObjectName( QStringLiteral( "formSearch" ) );
    search->setPlaceholderText( tr( "Найти язык" ) );
    search->setMinimumHeight( 54 );
    mainLayout->addWidget( search );
    mainLayout->addSpacing( 28 );

    auto* languageCards = new QHBoxLayout;
    languageCards->setSpacing( 12 );
    auto languageButton = [ content, languageCards ]( const QString& text, const QString& secondary, bool selected )
    {
        auto* button = new QPushButton( text + QStringLiteral( "\n" ) + secondary, content );
        button->setObjectName( selected ? QStringLiteral( "choiceCardSelected" ) : QStringLiteral( "choiceCard" ) );
        button->setCheckable( true );
        button->setChecked( selected );
        button->setMinimumHeight( 82 );
        languageCards->addWidget( button, 1 );
        return button;
    };
    auto* russian = languageButton( tr( "Русский" ), tr( "Россия" ), true );
    auto* english = languageButton( tr( "English" ), tr( "United States" ), false );
    auto* other = languageButton( tr( "Другие языки" ), tr( "Выбрать из списка" ), false );
    mainLayout->addLayout( languageCards );
    mainLayout->addSpacing( 36 );

    auto* timezoneTitle = new QLabel( tr( "Часовой пояс" ), content );
    timezoneTitle->setObjectName( QStringLiteral( "formSectionTitle" ) );
    mainLayout->addWidget( timezoneTitle );
    mainLayout->addSpacing( 12 );

    m_tzWidget = new TimeZoneWidget( m_config->zonesModel(), this );
    m_tzWidget->hide();

    QBoxLayout* zoneAndRegionLayout = new QHBoxLayout;
    zoneAndRegionLayout->setSpacing( 12 );
    auto* automatic = new QPushButton( tr( "Определять автоматически" ), content );
    automatic->setObjectName( QStringLiteral( "choicePillSelected" ) );
    automatic->setCheckable( true );
    automatic->setChecked( true );
    automatic->setMinimumHeight( 54 );
    zoneAndRegionLayout->addWidget( automatic, 1 );

    m_regionLabel = new QLabel( this );
    m_regionLabel->hide();

    m_regionCombo = new QComboBox( this );
    m_regionCombo->setSizePolicy( QSizePolicy::Expanding, QSizePolicy::Preferred );
    m_regionCombo->setObjectName( QStringLiteral( "formCombo" ) );
    m_regionCombo->setMinimumHeight( 54 );
    m_regionLabel->setBuddy( m_regionCombo );

    m_zoneLabel = new QLabel( this );
    m_zoneLabel->hide();

    m_zoneCombo = new QComboBox( this );
    m_zoneCombo->setSizePolicy( QSizePolicy::Expanding, QSizePolicy::Preferred );
    m_zoneCombo->setObjectName( QStringLiteral( "formCombo" ) );
    m_zoneCombo->setMinimumHeight( 54 );
    m_zoneCombo->setEnabled( false );
    zoneAndRegionLayout->addWidget( m_zoneCombo );
    m_zoneLabel->setBuddy( m_zoneCombo );
    m_regionCombo->hide();

    m_localeLabel = new QLabel( this );
    m_localeLabel->hide();

    m_localeChangeButton = new QPushButton( this );
    m_localeChangeButton->hide();

    m_formatsLabel = new QLabel( this );
    m_formatsLabel->hide();

    m_formatsChangeButton = new QPushButton( this );
    m_formatsChangeButton->hide();

    mainLayout->addLayout( zoneAndRegionLayout );
    mainLayout->addStretch( 1 );
    auto* line = new QFrame( content );
    line->setObjectName( QStringLiteral( "formSeparator" ) );
    line->setFrameShape( QFrame::HLine );
    mainLayout->addWidget( line );
    mainLayout->addSpacing( 18 );
    auto* actions = new QHBoxLayout;
    auto* back = new QPushButton( tr( "Назад" ), content );
    auto* done = new QPushButton( tr( "Готово" ), content );
    back->setObjectName( QStringLiteral( "secondaryAction" ) );
    done->setObjectName( QStringLiteral( "primaryAction" ) );
    back->setMinimumWidth( 160 );
    done->setMinimumWidth( 190 );
    actions->addWidget( back );
    actions->addStretch();
    actions->addWidget( done );
    mainLayout->addLayout( actions );

    // Set up the location before connecting signals, to avoid a signal
    // storm as various parts interact.
    {
        auto* regions = m_config->regionModel();
        auto* zones = m_config->regionalZonesModel();
        auto* location = m_config->currentLocation();
        zones->setRegion( location->region() );
        m_regionCombo->setModel( regions );
        m_zoneCombo->setModel( zones );
        m_tzWidget->setCurrentLocation( location );
        locationChanged( location );  // doesn't inform TZ widget
    }

    connect( config, &Config::currentLCStatusChanged, m_formatsLabel, &QLabel::setText );
    connect( config, &Config::currentLanguageStatusChanged, m_localeLabel, &QLabel::setText );
    connect( config, &Config::currentLocationChanged, m_tzWidget, &TimeZoneWidget::setCurrentLocation );
    connect( config, &Config::currentLocationChanged, this, &LocalePage::locationChanged );
    connect( m_tzWidget,
             &TimeZoneWidget::locationChanged,
             config,
             QOverload< const Calamares::Locale::TimeZoneData* >::of( &Config::setCurrentLocation ) );

    connect( m_regionCombo, QOverload< int >::of( &QComboBox::currentIndexChanged ), this, &LocalePage::regionChanged );
    connect( m_zoneCombo, QOverload< int >::of( &QComboBox::currentIndexChanged ), this, &LocalePage::zoneChanged );

    connect( m_localeChangeButton, &QPushButton::clicked, this, &LocalePage::changeLocale );
    connect( m_formatsChangeButton, &QPushButton::clicked, this, &LocalePage::changeFormats );
    connect( russian, &QPushButton::clicked, this, [ this ] { m_config->setLanguageExplicitly( QStringLiteral( "ru_RU.UTF-8" ) ); } );
    connect( english, &QPushButton::clicked, this, [ this ] { m_config->setLanguageExplicitly( QStringLiteral( "en_US.UTF-8" ) ); } );
    connect( other, &QPushButton::clicked, this, &LocalePage::changeLocale );
    connect( automatic, &QPushButton::toggled, this, [ this ]( bool enabled ) { m_zoneCombo->setEnabled( !enabled ); } );
    connect( search, &QLineEdit::textChanged, this, [ russian, english, other ]( const QString& text ) {
        const QString needle = text.trimmed();
        russian->setVisible( needle.isEmpty() || russian->text().contains( needle, Qt::CaseInsensitive ) );
        english->setVisible( needle.isEmpty() || english->text().contains( needle, Qt::CaseInsensitive ) );
        other->setVisible( needle.isEmpty() || other->text().contains( needle, Qt::CaseInsensitive ) );
    } );
    auto returnToStart = [] {
        Calamares::ViewManager::instance()->goToStep( QStringLiteral( "users" ) );
    };
    connect( back, &QPushButton::clicked, this, returnToStart );
    connect( done, &QPushButton::clicked, this, returnToStart );

    CALAMARES_RETRANSLATE_SLOT( &LocalePage::updateLocaleLabels );
}


LocalePage::~LocalePage() {}


void
LocalePage::updateLocaleLabels()
{
    m_regionLabel->setText( tr( "Region:", "@label" ) );
    m_zoneLabel->setText( tr( "Zone:", "@label" ) );
    m_localeChangeButton->setText( tr( "&Change…", "@button" ) );
    m_formatsChangeButton->setText( tr( "&Change…", "@button" ) );
    m_localeLabel->setText( m_config->currentLanguageStatus() );
    m_formatsLabel->setText( m_config->currentLCStatus() );
}


void
LocalePage::onActivate()
{
    m_regionCombo->setFocus();
    updateLocaleLabels();
}


void
LocalePage::regionChanged( int currentIndex )
{
    using namespace Calamares::Locale;

    QString selectedRegion = m_regionCombo->itemData( currentIndex ).toString();
    {
        cSignalBlocker z( m_zoneCombo );
        m_config->regionalZonesModel()->setRegion( selectedRegion );
    }
    m_zoneCombo->currentIndexChanged( 0 );
}

void
LocalePage::zoneChanged( int currentIndex )
{
    if ( !m_blockTzWidgetSet )
    {
        m_config->setCurrentLocation( m_regionCombo->currentData().toString(),
                                      m_zoneCombo->itemData( currentIndex ).toString() );
    }
}

void
LocalePage::locationChanged( const Calamares::Locale::TimeZoneData* location )
{
    if ( !location )
    {
        return;
    }
    cScopedAssignment b( &m_blockTzWidgetSet, true, false );

    // Set region index
    int index = m_regionCombo->findData( location->region() );
    if ( index < 0 )
    {
        return;
    }

    m_regionCombo->setCurrentIndex( index );

    // Set zone index
    index = m_zoneCombo->findData( location->zone() );
    if ( index < 0 )
    {
        return;
    }

    m_zoneCombo->setCurrentIndex( index );
}

void
LocalePage::changeLocale()
{
    QPointer< LCLocaleDialog > dlg(
        new LCLocaleDialog( m_config->localeConfiguration().language(), m_config->supportedLocales(), this ) );
    dlg->exec();
    if ( dlg && dlg->result() == QDialog::Accepted && !dlg->selectedLCLocale().isEmpty() )
    {
        m_config->setLanguageExplicitly( dlg->selectedLCLocale() );
        updateLocaleLabels();
    }

    delete dlg;
}


void
LocalePage::changeFormats()
{
    QPointer< LCLocaleDialog > dlg(
        new LCLocaleDialog( m_config->localeConfiguration().lc_numeric, m_config->supportedLocales(), this ) );
    dlg->exec();
    if ( dlg && dlg->result() == QDialog::Accepted && !dlg->selectedLCLocale().isEmpty() )
    {
        m_config->setLCLocaleExplicitly( dlg->selectedLCLocale() );
        updateLocaleLabels();
    }

    delete dlg;
}
