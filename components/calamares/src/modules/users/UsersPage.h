/* === This file is part of Calamares - <https://calamares.io> ===
 *
 *   SPDX-FileCopyrightText: 2007 Free Software Foundation, Inc.
 *   SPDX-FileCopyrightText: 2014-2015 Teo Mrnjavac <teo@kde.org>
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

#ifndef USERSPAGE_H
#define USERSPAGE_H

#include <QWidget>

class Config;

class QLabel;
class QComboBox;
class QHBoxLayout;
class QResizeEvent;

namespace Ui
{
class Page_UserSetup;
}  // namespace Ui

class UsersPage : public QWidget
{
    Q_OBJECT
public:
    explicit UsersPage( Config* config, QWidget* parent = nullptr );
    ~UsersPage() override;

    void onActivate();

protected:
    void resizeEvent( QResizeEvent* event ) override;

protected slots:
    void onFullNameTextEdited( const QString& );
    void reportLoginNameStatus( const QString& );
    void reportHostNameStatus( const QString& );
    void onReuseUserPasswordChanged( const int );
    void reportUserPasswordStatus( int, const QString& );
    void reportRootPasswordStatus( int, const QString& );

    void onActiveDirectoryToggled( bool checked );

private:
    void retranslate();
    void updateGeneratedFieldsVisibility( bool visible );
    void buildKaskadStartPage();
    void updateStartGeometry();

    Ui::Page_UserSetup* ui;
    Config* m_config;
    QComboBox* m_diskCombo = nullptr;
    QLabel* m_loginHint = nullptr;
    QLabel* m_deviceHint = nullptr;
    QWidget* m_loginBox = nullptr;
    QWidget* m_deviceBox = nullptr;
    QWidget* m_startContent = nullptr;
    QWidget* m_startLeft = nullptr;
    QHBoxLayout* m_startColumns = nullptr;
};

#endif  // USERSPAGE_H
