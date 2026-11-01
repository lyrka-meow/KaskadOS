/* === This file is part of Calamares - <https://calamares.io> ===
 *
 *   SPDX-FileCopyrightText: 2014-2015 Teo Mrnjavac <teo@kde.org>
 *   SPDX-FileCopyrightText: 2017-2018 Adriaan de Groot <groot@kde.org>
 *   SPDX-FileCopyrightText: 2019 Collabora Ltd <arnaud.ferraris@collabora.com>
 *   SPDX-FileCopyrightText: 2026 KaskadOS contributors
 *   SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "FinishedPage.h"

#include "Config.h"
#include "ui_FinishedPage.h"

#include "Branding.h"
#include "Settings.h"
#include "ViewManager.h"
#include "utils/Retranslator.h"

#include <QFocusEvent>
#include <QIcon>
#include <QPainter>
#include <QPixmap>
#include <QProgressBar>
#include <QPushButton>
#include <QTimer>

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
}

FinishedPage::FinishedPage( Config* config, QWidget* parent )
    : QWidget( parent )
    , ui( new Ui::FinishedPage )
    , m_config( config )
    , m_countdownTimer( new QTimer( this ) )
{
    ui->setupUi( this );

    ui->pageTitle->setObjectName( QStringLiteral( "finishedPageTitle" ) );
    ui->finishedContent->setObjectName( QStringLiteral( "finishedContent" ) );
    ui->finishedBody->setObjectName( QStringLiteral( "finishedBody" ) );
    ui->successIcon->setObjectName( QStringLiteral( "finishedSuccessIcon" ) );
    ui->mainText->setObjectName( QStringLiteral( "finishedHeadline" ) );
    ui->countdownText->setObjectName( QStringLiteral( "finishedCountdown" ) );
    ui->countdownProgress->setObjectName( QStringLiteral( "finishedProgress" ) );
    ui->secondsChip->setObjectName( QStringLiteral( "finishedSecondsChip" ) );
    ui->noteIcon->setObjectName( QStringLiteral( "finishedNoteIcon" ) );
    ui->mediaNote->setObjectName( QStringLiteral( "finishedMediaNote" ) );
    ui->stayButton->setObjectName( QStringLiteral( "secondaryAction" ) );
    ui->restartButton->setObjectName( QStringLiteral( "primaryAction" ) );

    const QFont symbolsFont( QStringLiteral( "Material Symbols Rounded" ) );
    ui->successIcon->setFont( symbolsFont );
    ui->noteIcon->setFont( symbolsFont );
    ui->restartButton->setIcon(
        materialIcon( QStringLiteral( "restart_alt" ), QColor( QStringLiteral( "#113422" ) ), 22 ) );
    ui->stayButton->setIcon(
        materialIcon( QStringLiteral( "pause" ), QColor( QStringLiteral( "#9BD9B4" ) ), 22 ) );
    ui->restartButton->setIconSize( QSize( 28, 28 ) );
    ui->stayButton->setIconSize( QSize( 28, 28 ) );

    ui->mainText->setAlignment( Qt::AlignLeft | Qt::AlignVCenter );
    ui->mainText->setWordWrap( true );

    m_countdownTimer->setInterval( 1000 );
    connect( m_countdownTimer, &QTimer::timeout, this, [ this ]()
    {
        --m_secondsRemaining;
        if ( m_secondsRemaining <= 0 )
        {
            m_countdownTimer->stop();
            quitWithRestart( true );
            return;
        }
        updateCountdownText();
    } );
    connect( ui->restartButton, &QPushButton::clicked, this, [ this ]() { quitWithRestart( true ); } );
    connect( ui->stayButton, &QPushButton::clicked, this, [ this ]() { quitWithRestart( false ); } );

    CALAMARES_RETRANSLATE_SLOT( &FinishedPage::retranslate );
}

void
FinishedPage::startCountdown()
{
    if ( m_failure.has_value() )
    {
        stopCountdown();
        ui->countdownText->hide();
        ui->countdownProgress->hide();
        ui->secondsChip->hide();
        ui->noteIcon->hide();
        ui->mediaNote->hide();
        ui->restartButton->hide();
        return;
    }

    m_secondsRemaining = 10;
    ui->countdownText->show();
    ui->countdownProgress->show();
    ui->secondsChip->show();
    ui->noteIcon->show();
    ui->mediaNote->show();
    ui->restartButton->show();
    updateCountdownText();
    if ( m_config->restartNowMode() == Config::RestartMode::Never )
    {
        // Preview mode: render the complete final screen without closing or rebooting.
        stopCountdown();
    }
    else
    {
        m_countdownTimer->start();
    }
}

void
FinishedPage::stopCountdown()
{
    m_countdownTimer->stop();
}

void
FinishedPage::updateCountdownText()
{
    ui->countdownText->setText(
        tr( "Компьютер автоматически перезагрузится через %n секунду.", "", m_secondsRemaining ) );
    ui->secondsChip->setText( tr( "%n секунд", "", m_secondsRemaining ) );
    ui->countdownProgress->setValue( m_secondsRemaining * 10 );
}

void
FinishedPage::quitWithRestart( bool restart )
{
    stopCountdown();
    m_config->setRestartNowWanted( restart );
    Calamares::ViewManager::instance()->quit();
}

void
FinishedPage::focusInEvent( QFocusEvent* e )
{
    ui->restartButton->setFocus();
    e->accept();
}

void
FinishedPage::onInstallationFailed( const QString& message, const QString& details )
{
    m_failure = !message.isEmpty() ? message : details;
    stopCountdown();
    retranslate();
}

void
FinishedPage::retranslate()
{
    const auto* branding = Calamares::Branding::instance();
    ui->retranslateUi( this );

    if ( !m_failure.has_value() )
    {
        if ( Calamares::Settings::instance()->isSetupMode() )
        {
            ui->pageTitle->setText( tr( "%1 настроена" ).arg( branding->shortProductName() ) );
            ui->mainText->setText( tr( "Система готова к первому запуску" ) );
        }
        else
        {
            ui->pageTitle->setText( tr( "%1 установлена" ).arg( branding->shortProductName() ) );
            ui->mainText->setText( tr( "Система готова к первому запуску" ) );
        }
        ui->stayButton->setText( tr( "Остаться в установочной среде" ) );
        ui->restartButton->setText( tr( "Перезагрузить сейчас" ) );
        updateCountdownText();
    }
    else
    {
        const QString message = m_failure.value();
        ui->pageTitle->setText(
            Calamares::Settings::instance()->isSetupMode()
                ? tr( "Не удалось настроить %1" ).arg( branding->shortProductName() )
                : tr( "Не удалось установить %1" ).arg( branding->shortProductName() ) );
        ui->mainText->setText( message );
        ui->countdownText->hide();
        ui->countdownProgress->hide();
        ui->secondsChip->hide();
        ui->noteIcon->hide();
        ui->mediaNote->hide();
        ui->restartButton->hide();
        ui->stayButton->setText( tr( "Закрыть" ) );
    }
}
