/* === This file is part of Calamares - <https://calamares.io> ===
 *
 *   SPDX-FileCopyrightText: 2007 Free Software Foundation, Inc.
 *   SPDX-FileCopyrightText: 2014-2016 Teo Mrnjavac <teo@kde.org>
 *   SPDX-FileCopyrightText: 2017-2018 Adriaan de Groot <groot@kde.org>
 *   SPDX-License-Identifier: GPL-3.0-or-later
 *
 *   Portions from the Manjaro Installation Framework
 *   by Roland Singer <roland@manjaro.org>
 *   Copyright (C) 2007 Free Software Foundation, Inc.
 *
 *   Calamares is Free Software: see the License-Identifier above.
 *
 */

#include "KeyboardPage.h"

#include "Config.h"
#include "KeyboardLayoutModel.h"
#include "SetKeyboardLayoutJob.h"
#include "keyboardwidget/keyboardpreview.h"
#include "ui_KeyboardPage.h"

#include "GlobalStorage.h"
#include "JobQueue.h"
#include "utils/Logger.h"
#include "utils/Retranslator.h"
#include "utils/String.h"
#include "ViewManager.h"

#include <QComboBox>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>

namespace
{
void
clearLayout( QLayout* layout )
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

class LayoutItem : public QListWidgetItem
{
public:
    QString data;

    ~LayoutItem() override;
};

LayoutItem::~LayoutItem() {}

KeyboardPage::KeyboardPage( Config* config, QWidget* parent )
    : QWidget( parent )
    , ui( new Ui::Page_Keyboard )
    , m_keyboardPreview( new KeyBoardPreview( this ) )
    , m_config( config )
{
    ui->setupUi( this );

    auto* title = new QLabel( tr( "Клавиатура" ), this );
    title->setProperty( "heading", true );
    auto* subtitle = new QLabel( tr( "Раскладки и переключение языка." ), this );
    subtitle->setObjectName( QStringLiteral( "pageSubtitle" ) );
    ui->verticalLayout->insertWidget( 0, subtitle );
    ui->verticalLayout->insertWidget( 0, title );

    // The generic PC-105 model is correct for normal installations. Keep the
    // model in Config, but do not make the user choose an implementation detail.
    ui->label->hide();
    ui->physicalModelSelector->hide();
    ui->buttonRestore->hide();

    // Keyboard Preview
    ui->KBPreviewLayout->addWidget( m_keyboardPreview );

    {
        auto* model = config->keyboardModels();
        model->setCurrentIndex();  // To default PC105
        ui->physicalModelSelector->setModel( model );
        ui->physicalModelSelector->setCurrentIndex( model->currentIndex() );
    }
    {
        auto* model = config->keyboardLayouts();
        ui->layoutSelector->setModel( model );
        ui->layoutSelector->setCurrentIndex( model->index( model->currentIndex() ) );
    }
    {
        auto* model = config->keyboardVariants();
        ui->variantSelector->setModel( model );
        ui->variantSelector->setCurrentIndex( model->index( model->currentIndex() ) );
        cDebug() << "Variants now total=" << model->rowCount() << "selected=" << model->currentIndex();
    }

    auto* additionalCard = new QWidget( this );
    additionalCard->setObjectName( QStringLiteral( "keyboardOptionsCard" ) );
    auto* additionalLayout = new QHBoxLayout( additionalCard );
    additionalLayout->setContentsMargins( 20, 12, 20, 12 );
    additionalLayout->setSpacing( 16 );

    auto* additionalLabel = new QLabel( tr( "Дополнительная раскладка" ), additionalCard );
    auto* additionalSelector = new QComboBox( additionalCard );
    additionalSelector->setObjectName( QStringLiteral( "additionalLayoutSelector" ) );
    additionalSelector->addItem( tr( "Автоматически" ), QVariant() );
    additionalSelector->addItem( tr( "Не добавлять" ), QStringLiteral( "" ) );
    for ( int i = 0; i < config->keyboardLayouts()->rowCount(); ++i )
    {
        const QModelIndex index = config->keyboardLayouts()->index( i );
        additionalSelector->addItem( index.data( Qt::DisplayRole ).toString(), config->keyboardLayouts()->key( i ) );
    }
    additionalSelector->setMinimumWidth( 260 );

    auto* switcherLabel = new QLabel( tr( "Переключение" ), additionalCard );
    auto* switcherSelector = new QComboBox( additionalCard );
    switcherSelector->setObjectName( QStringLiteral( "groupSwitcherSelector" ) );
    switcherSelector->addItem( tr( "Alt + Shift" ), QStringLiteral( "grp:alt_shift_toggle" ) );
    switcherSelector->addItem( tr( "Ctrl + Shift" ), QStringLiteral( "grp:ctrl_shift_toggle" ) );
    switcherSelector->addItem( tr( "Caps Lock" ), QStringLiteral( "grp:caps_toggle" ) );

    additionalLayout->addWidget( additionalLabel );
    additionalLayout->addWidget( additionalSelector, 1 );
    additionalLayout->addSpacing( 16 );
    additionalLayout->addWidget( switcherLabel );
    additionalLayout->addWidget( switcherSelector );
    ui->verticalLayout->insertWidget( ui->verticalLayout->count() - 1, additionalCard );

    connect( additionalSelector,
             QOverload< int >::of( &QComboBox::currentIndexChanged ),
             [ config, additionalSelector ]( int index )
             {
                 if ( index == 0 )
                 {
                     config->setAdditionalLayoutOverride( QString() );
                 }
                 else
                 {
                     config->setAdditionalLayoutOverride( additionalSelector->currentData().toString() );
                 }
             } );
    connect( switcherSelector,
             QOverload< int >::of( &QComboBox::currentIndexChanged ),
             [ config, switcherSelector ]( int )
             { config->setGroupSwitcher( switcherSelector->currentData().toString() ); } );
    connect( ui->buttonRestore,
             &QPushButton::clicked,
             [ config = config ] { config->keyboardModels()->setCurrentIndex(); } );

    connect( ui->physicalModelSelector,
             QOverload< int >::of( &QComboBox::currentIndexChanged ),
             config->keyboardModels(),
             QOverload< int >::of( &XKBListModel::setCurrentIndex ) );
    connect( config->keyboardModels(),
             &KeyboardModelsModel::currentIndexChanged,
             ui->physicalModelSelector,
             &QComboBox::setCurrentIndex );

    connect( ui->layoutSelector->selectionModel(),
             &QItemSelectionModel::currentChanged,
             [ this ]( const QModelIndex& current )
             { m_config->keyboardLayouts()->setCurrentIndex( current.row() ); } );
    connect( config->keyboardLayouts(),
             &KeyboardLayoutModel::currentIndexChanged,
             [ this ]( int index )
             {
                 ui->layoutSelector->setCurrentIndex( m_config->keyboardLayouts()->index( index ) );
                 m_keyboardPreview->setLayout( m_config->keyboardLayouts()->key( index ) );
                 m_keyboardPreview->setVariant(
                     m_config->keyboardVariants()->key( m_config->keyboardVariants()->currentIndex() ) );
             } );

    connect( ui->variantSelector->selectionModel(),
             &QItemSelectionModel::currentChanged,
             [ this ]( const QModelIndex& current )
             { m_config->keyboardVariants()->setCurrentIndex( current.row() ); } );
    connect( config->keyboardVariants(),
             &KeyboardVariantsModel::currentIndexChanged,
             [ this ]( int index )
             {
                 ui->variantSelector->setCurrentIndex( m_config->keyboardVariants()->index( index ) );
                 m_keyboardPreview->setVariant( m_config->keyboardVariants()->key( index ) );
             } );

    // Recompose the existing functional controls into the KaskadOS mockup.
    m_keyboardPreview->hide();
    ui->layoutSelector->hide();
    ui->variantSelector->hide();
    additionalCard->hide();
    clearLayout( ui->verticalLayout );
    ui->verticalLayout->setContentsMargins( 40, 22, 40, 22 );
    ui->verticalLayout->setSpacing( 0 );

    auto* centering = new QHBoxLayout;
    auto* content = new QWidget( this );
    content->setObjectName( QStringLiteral( "kaskadFormPage" ) );
    content->setMinimumWidth( 860 );
    content->setMaximumWidth( 1040 );
    auto* contentLayout = new QVBoxLayout( content );
    contentLayout->setContentsMargins( 0, 0, 0, 0 );
    contentLayout->setSpacing( 0 );
    centering->addStretch();
    centering->addWidget( content, 1 );
    centering->addStretch();

    ui->verticalLayout->addLayout( centering, 1 );

    title->setObjectName( QStringLiteral( "formPageTitle" ) );
    subtitle->setObjectName( QStringLiteral( "formPageSubtitle" ) );
    subtitle->setText( tr( "Раскладки и модель клавиатуры." ) );
    title->setParent( content );
    subtitle->setParent( content );
    contentLayout->addWidget( title );
    contentLayout->addSpacing( 5 );
    contentLayout->addWidget( subtitle );
    contentLayout->addSpacing( 30 );

    auto* modelTitle = new QLabel( tr( "Модель клавиатуры" ), content );
    modelTitle->setObjectName( QStringLiteral( "formSectionTitle" ) );
    contentLayout->addWidget( modelTitle );
    contentLayout->addSpacing( 10 );
    ui->physicalModelSelector->setParent( content );
    ui->physicalModelSelector->setObjectName( QStringLiteral( "formCombo" ) );
    ui->physicalModelSelector->setMinimumHeight( 54 );
    ui->physicalModelSelector->show();
    contentLayout->addWidget( ui->physicalModelSelector );
    contentLayout->addSpacing( 30 );

    auto* layoutsTitle = new QLabel( tr( "Раскладки" ), content );
    layoutsTitle->setObjectName( QStringLiteral( "formSectionTitle" ) );
    contentLayout->addWidget( layoutsTitle );
    contentLayout->addSpacing( 10 );
    auto* cards = new QVBoxLayout;
    cards->setSpacing( 6 );
    auto* russianCard = new QPushButton( tr( "Русская" ), content );
    auto* englishCard = new QPushButton( tr( "English (US)" ), content );
    russianCard->setObjectName( QStringLiteral( "layoutCardSelected" ) );
    englishCard->setObjectName( QStringLiteral( "layoutCard" ) );
    russianCard->setMinimumHeight( 58 );
    englishCard->setMinimumHeight( 58 );
    cards->addWidget( russianCard );
    cards->addWidget( englishCard );
    contentLayout->addLayout( cards );
    auto selectLayout = [ config ]( const QStringList& needles ) {
        auto* layouts = config->keyboardLayouts();
        for ( int row = 0; row < layouts->rowCount(); ++row )
        {
            const QString name = layouts->index( row ).data( Qt::DisplayRole ).toString();
            for ( const QString& needle : needles )
            {
                if ( name.contains( needle, Qt::CaseInsensitive ) )
                {
                    layouts->setCurrentIndex( row );
                    return;
                }
            }
        }
    };
    connect( russianCard, &QPushButton::clicked, this, [ selectLayout ] { selectLayout( { QStringLiteral( "Russian" ), QStringLiteral( "Рус" ) } ); } );
    connect( englishCard, &QPushButton::clicked, this, [ selectLayout ] { selectLayout( { QStringLiteral( "English (US)" ), QStringLiteral( "English" ) } ); } );
    contentLayout->addSpacing( 26 );

    auto* testRow = new QHBoxLayout;
    testRow->setSpacing( 12 );
    ui->LE_TestKeyboard->setParent( content );
    ui->LE_TestKeyboard->setObjectName( QStringLiteral( "formSearch" ) );
    ui->LE_TestKeyboard->setPlaceholderText( tr( "Проверить раскладку" ) );
    ui->LE_TestKeyboard->setMinimumHeight( 54 );
    auto* switchChip = new QPushButton( tr( "Alt + Shift" ), content );
    switchChip->setObjectName( QStringLiteral( "choicePillSelected" ) );
    switchChip->setMinimumWidth( 170 );
    testRow->addWidget( ui->LE_TestKeyboard, 1 );
    testRow->addWidget( switchChip );
    contentLayout->addLayout( testRow );
    contentLayout->addStretch( 1 );

    auto* line = new QFrame( content );
    line->setObjectName( QStringLiteral( "formSeparator" ) );
    line->setFrameShape( QFrame::HLine );
    contentLayout->addWidget( line );
    contentLayout->addSpacing( 18 );
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
    contentLayout->addLayout( actions );
    auto returnToStart = [] {
        Calamares::ViewManager::instance()->goToStep( QStringLiteral( "users" ) );
    };
    connect( back, &QPushButton::clicked, this, returnToStart );
    connect( done, &QPushButton::clicked, this, returnToStart );

    CALAMARES_RETRANSLATE_SLOT( &KeyboardPage::retranslate );
}

KeyboardPage::~KeyboardPage()
{
    delete ui;
}

void
KeyboardPage::retranslate()
{
    ui->retranslateUi( this );
    m_config->retranslate();
}
