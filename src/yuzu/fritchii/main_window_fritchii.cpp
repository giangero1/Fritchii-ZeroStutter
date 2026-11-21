// SPDX-License-Identifier: GPL-3.0-or-later

// MainWindow's Fritchii setup, kept out of main_window.cpp so merges stay clean. It runs
// once at the end of the constructor and does nothing in a build without the Fritchii look.

#include <QAction>
#include <QApplication>
#include <QDesktopServices>
#include <QMessageBox>
#include <QMenu>
#include <QPushButton>
#include <QShortcut>
#include <QStatusBar>
#include <QTimer>
#include <QUrl>

#include "common/nx2_hitch.h"
#include "common/oot_menu_grace.h"
#include "core/core.h"
#include "hid_core/frontend/emulated_controller.h"
#include "hid_core/frontend/emulated_devices.h"
#include "hid_core/hid_core.h"
#include "qt_common/config/uisettings.h"
#include "qt_common/qt_common.h"
#include "qt_common/util/game.h"
#include "ui_main.h"
#include "yuzu/fritchii/fritchii_ui.h"
#include "yuzu/bootmanager.h"
#include "yuzu/fritchii/game_controls.h"
#include "yuzu/fritchii/home.h"
#include "yuzu/fritchii/precompile_gate.h"
#include "yuzu/fritchii/whats_new.h"
#include "yuzu/game/game_list.h"
#include "yuzu/main_window.h"
#include "yuzu/multiplayer/state.h"
#include "yuzu/util/clickable_label.h"

void MainWindow::SetUpFritchiiUi() {
    if (!FritchiiUi::Enabled()) {
        return;
    }

    // For players whose cache went bad: the game's whole shader folder (pipeline caches,
    // precompiled pipelines and what their preparation kept), after a confirmation. Not while a
    // game runs, which has those files open.
    constexpr u64 OcarinaOfTime = 0x0400486024DEC000ULL;
    const auto delete_shader_cache = [this](u64 program_id) {
        const QString title = tr("Delete Shader Cache");
        if (emulation_running || boot_in_progress) {
            QMessageBox::information(this, title, tr("Stop the game first."));
            return;
        }
        QMessageBox box(QMessageBox::Warning, title,
                        program_id == OcarinaOfTime ? tr("Delete OoT's shader cache?")
                                                    : tr("Delete this game's shader cache?"),
                        QMessageBox::NoButton, this);
        box.setInformativeText(tr("Only if the game crashes or looks wrong because of it. The "
                                  "shaders are prepared again on the next start."));
        QPushButton* remove = box.addButton(tr("Delete"), QMessageBox::DestructiveRole);
        box.setDefaultButton(box.addButton(QMessageBox::Cancel));
        box.exec();
        if (box.clickedButton() == remove) {
            QtCommon::Game::RemoveAllTransferableShaderCaches(program_id);
        }
    };

    FritchiiUi::RestructureMenus(
        *ui, *this,
        {.export_log = [this] { OnExportLog(); },
         .whats_new = [this] { FritchiiUi::ShowWhatsNew(this); },
         .delete_shader_cache = [delete_shader_cache] { delete_shader_cache(OcarinaOfTime); }});

    const auto show_shader_setup = [this](bool startup_offer) {
        const QString dialog_name = QStringLiteral("FritchiiShaderSetup");
        QWidget* parent = render_window && render_window->isVisible() ? render_window->window()
                                                                    : this;
        if (auto* existing = parent->findChild<QMessageBox*>(dialog_name)) {
            existing->raise();
            existing->activateWindow();
            return;
        }

        auto* box = new QMessageBox(QMessageBox::Information, tr("Ocarina of Time shader setup"),
                                    tr("Frizti's recipe prepares about 120,000 shader pipelines "
                                       "for Ocarina of Time."),
                                    QMessageBox::NoButton, parent);
        box->setObjectName(dialog_name);
        box->setAttribute(Qt::WA_DeleteOnClose);
        QString instructions = tr(
            "<p>The separate shader cache pack contains about <b>19,000 shaders</b>. Without "
            "the full preparation, new shaders compile as you play and can cause stutter, "
            "especially when entering new areas.</p>"
            "<p><b>Set up Zero-Stutter</b></p>"
            "<ol>"
            "<li>Download <b>Fritchii-v6.2-Windows-x64.zip</b> from <b>Assets</b> on Frizti's "
            "release page and extract it.</li>"
            "<li>With Frizti's written permission, copy the whole <b>recipes</b> folder, "
            "including <b>RECIPE-LICENSE.txt</b>, next to Zero-Stutter's "
            "<b>fritchii.exe</b>.</li>"
            "<li>Restart Zero-Stutter and launch Ocarina of Time. <b>Preparing shaders</b> "
            "can take 10-20 minutes the first time. Later launches reuse that work.</li>"
            "</ol>"
            "<p>You can also run the extracted <b>fritchii.exe</b> to play in the official "
            "build.</p>");
        if (!startup_offer) {
            instructions += tr("<p>With the full recipe, the game log typically shows "
                               "<b>116,351 graphics</b> and <b>4,085 compute</b> pipelines.</p>");
        }
        instructions += tr("<p>Shader precompile recipe by Frizti (Fritchii). "
                           "<a href=\"https://github.com/Frizti/Fritchii/blob/"
                           "fritchii-v6.2/LICENSES/Fritchii-Recipe.txt\">Recipe terms</a></p>");
        box->setInformativeText(instructions);
        box->setTextInteractionFlags(Qt::TextBrowserInteraction);
        QPushButton* download = box->addButton(tr("Open official Fritchii download"),
                                               QMessageBox::AcceptRole);
        QPushButton* dismiss = box->addButton(startup_offer ? tr("Keep playing") : tr("Close"),
                                              QMessageBox::RejectRole);
        box->setDefaultButton(dismiss);
        box->setEscapeButton(dismiss);
        connect(box, &QMessageBox::finished, this, [this, box, download, startup_offer](int) {
            if (startup_offer) {
                UISettings::values.fritchii_shader_setup_seen.SetValue(true);
                OnSaveConfig();
            }
            if (box->clickedButton() == download) {
                const QUrl url(QStringLiteral(
                    "https://github.com/Frizti/Fritchii/releases/tag/fritchii-v6.2"));
                if (!QDesktopServices::openUrl(url)) {
                    auto* notice = new QMessageBox(QMessageBox::Information,
                                                   tr("Open official Fritchii download"),
                                                   url.toString(), QMessageBox::Close, this);
                    notice->setTextInteractionFlags(Qt::TextSelectableByMouse |
                                                    Qt::TextSelectableByKeyboard);
                    notice->setAttribute(Qt::WA_DeleteOnClose);
                    notice->open();
                }
            }
        });
        if (startup_offer) {
            connect(this, &MainWindow::EmulationStopping, box, &QMessageBox::reject);
        }
        box->open();
    };
    auto* shader_setup = ui->menu_Help->addAction(tr("Shader setup"));
    connect(shader_setup, &QAction::triggered, this,
            [show_shader_setup] { show_shader_setup(false); });

    const bool trace_menu = Common::Nx2Hitch::MenuTraceEnabled();
    if (trace_menu) {
        const auto add_marker = [this](const QKeySequence& key, const char* menu) {
            auto* shortcut = new QShortcut(key, this);
            shortcut->setContext(Qt::ApplicationShortcut);
            shortcut->setAutoRepeat(false);
            connect(shortcut, &QShortcut::activated, this, [this, menu] {
                if (emulation_running) {
                    Common::Nx2Hitch::MarkMenuTrace(menu);
                }
            });
        };
        add_marker(QKeySequence{Qt::CTRL | Qt::ALT | Qt::Key_F11}, "L1 inventory");
        add_marker(QKeySequence{Qt::CTRL | Qt::ALT | Qt::Key_F12}, "Start/Esc pause menu");
    }

    if (trace_menu || Common::OotMenuGrace::Enabled()) {
        auto* input_trace_timer = new QTimer(this);
        connect(input_trace_timer, &QTimer::timeout, this,
                [this, previous = Core::HID::NpadButtonState{},
                 grace = Common::OotMenuGrace::InputState{}]() mutable {
                    if (!emulation_running ||
                        QtCommon::system->GetApplicationProcessProgramID() != OcarinaOfTime) {
                        previous = {};
                        if (Common::OotMenuGrace::Enabled()) {
                            grace = {};
                            Common::OotMenuGrace::escape_pressed.store(false,
                                                                        std::memory_order_relaxed);
                            Common::OotMenuGrace::Publish({});
                        }
                        return;
                    }
                    auto& hid = QtCommon::system->HIDCore();
                    Core::HID::NpadButtonState buttons{};
                    for (const auto id : {Core::HID::NpadIdType::Player1,
                                          Core::HID::NpadIdType::Handheld}) {
                        const auto* controller = hid.GetEmulatedController(id);
                        if (controller->IsConnected()) {
                            buttons.raw |= controller->GetNpadButtons().raw;
                        }
                    }
                    if (Settings::values.keyboard_enabled.GetValue()) {
                        constexpr auto LeftArrow =
                            static_cast<size_t>(Core::HID::KeyboardKeyIndex::LeftArrow);
                        const auto keys = hid.GetEmulatedDevices()->GetKeyboard();
                        if ((keys.key[LeftArrow / 8] & (1U << (LeftArrow % 8))) != 0) {
                            buttons.left.Assign(true);
                        }
                    }
                    if (buttons.l.Value() != previous.l.Value()) {
                        Common::Nx2Hitch::MarkMenuTrace(buttons.l ? "L pressed" : "L released");
                    }
                    if (buttons.zl.Value() != previous.zl.Value()) {
                        Common::Nx2Hitch::MarkMenuTrace(buttons.zl ? "ZL pressed" : "ZL released");
                    }
                    if (buttons.left.Value() != previous.left.Value()) {
                        Common::Nx2Hitch::MarkMenuTrace(buttons.left ? "Left pressed" : "Left released");
                    }
                    const bool plus_pressed = buttons.plus && !previous.plus;
                    const bool back_pressed = buttons.b && !previous.b;
                    if (plus_pressed) {
                        Common::Nx2Hitch::MarkMenuTrace("Plus pressed");
                    }
                    if (back_pressed) {
                        Common::Nx2Hitch::MarkMenuTrace("B pressed");
                    }
                    if (Common::OotMenuGrace::Enabled()) {
                        const bool escape = Common::OotMenuGrace::escape_pressed.exchange(
                            false, std::memory_order_relaxed);
                        const bool ocarina_pressed = buttons.left && !previous.left;
                        Common::OotMenuGrace::Publish(grace.Update(
                            Common::OotMenuGrace::Clock::now(), buttons.l.Value(),
                            plus_pressed || escape, back_pressed, ocarina_pressed));
                    }
                    previous = buttons;
                });
        input_trace_timer->setTimerType(Qt::PreciseTimer);
        input_trace_timer->start(8);
    }

    // "What's new" once per version after an update, when nothing else is on screen: no other
    // dialog (first-launch question, update offer, restart note) and no game running.
    const bool used_before = Settings::values.oot_fps_asked.GetValue();
    if (FritchiiUi::ShouldShowWhatsNew(used_before)) {
        auto* timer = new QTimer(this);
        timer->setInterval(1500);
        connect(timer, &QTimer::timeout, this, [this, timer] {
            const bool first_question_pending =
                !launched_with_game && !Settings::values.oot_fps_asked.GetValue();
            if (QApplication::activeModalWidget() != nullptr || first_question_pending ||
                emulation_running || boot_in_progress) {
                return;
            }
            timer->stop();
            timer->deleteLater();
            FritchiiUi::MarkWhatsNewSeen();
            OnSaveConfig();
            FritchiiUi::ShowWhatsNew(this);
        });
        timer->start();
    } else if (!used_before) {
        OnSaveConfig(); // a first install recorded its version
    }

    // Status bar: the everyday controls stay (60/30 FPS, docked, volume); renderer, accuracy,
    // filter, anti-aliasing and effects move into one Graphics button. The old buttons stay
    // hidden: they still hold the state the rest of the window updates.
    for (QWidget* expert : {static_cast<QWidget*>(renderer_status_button),
                            static_cast<QWidget*>(gpu_accuracy_button),
                            static_cast<QWidget*>(filter_status_button),
                            static_cast<QWidget*>(aa_status_button),
                            static_cast<QWidget*>(post_shader_status_button),
                            static_cast<QWidget*>(refresh_button)}) {
        if (expert) {
            expert->hide();
        }
    }
    multiplayer_state->GetStatusText()->hide();
    FritchiiUi::GraphicsHooks graphics{
        .refresh =
            [this] {
                UpdateStatusButtons();
#ifdef HAS_RESHADE
                UpdatePostShaderText();
#endif
            },
        .renderer_locked = [this] { return !renderer_status_button->isEnabled(); },
        .open_settings = [this] { OnConfigure(); },
#ifdef HAS_RESHADE
        .open_effects = [this] { OnPostProcessingShaders(); },
#endif
    };
    statusBar()->insertPermanentWidget(0, FritchiiUi::MakeGraphicsButton(this, graphics));

    // Home screen and rail.
    FritchiiUi::HomeHooks home{
        .play = [this](const QString& path, u64 program_id) { OnGameListLoadFile(path, program_id); },
        .add_folder = [this] { OnGameListAddDirectory(); },
        .open_settings = [this] { OnConfigure(); },
        .game_settings =
            [this](u64 program_id, const std::string& path) {
                OpenPerGameConfiguration(program_id, path);
            },
        .delete_shader_cache = delete_shader_cache,
        .game_menu =
            [this](QMenu& menu, u64 program_id, const std::string& path) {
                game_list->AddGameMenu(menu, program_id, path);
            },
        .game_list_empty = [this] { return game_list->IsEmpty(); },
        .single_window = [this] { return ui->action_Single_Window_Mode->isChecked(); },
        .emulation_running = [this] { return emulation_running; },
        .model = game_list->GetModel(),
        .help_menu = ui->menu_Help,
        .classic_menus = {ui->menu_File, ui->menu_Emulation, ui->menu_View, ui->menu_Tools,
                          ui->menu_Help},
    };
    fritchii_home = new FritchiiUi::Home(this, ui->horizontalLayout, game_list,
                                         game_list_placeholder, std::move(home));
    connect(this, &MainWindow::EmulationStarting, fritchii_home,
            &FritchiiUi::Home::OnEmulationStarting);

    // In-game controls: the menu bar is gone and the rail steps aside while a game runs.
    auto* controls = new FritchiiUi::GameControls(
        this, {.render = [this] { return static_cast<QWidget*>(render_window); },
               .running = [] { return QtCommon::emu_thread && QtCommon::emu_thread->IsRunning(); },
               .pause = ui->action_Pause,
               .restart = ui->action_Restart,
               .stop = ui->action_Stop,
               .fullscreen = ui->action_Fullscreen,
               .menus = {ui->menu_File, ui->menu_Emulation, ui->menu_View, ui->menu_Tools,
                         ui->menu_Help}});
    connect(this, &MainWindow::EmulationStarting, controls, &FritchiiUi::GameControls::Start);
    connect(this, &MainWindow::EmulationStopping, controls, &FritchiiUi::GameControls::Stop);

    // "Preparing shaders" before the game starts when its precompiled pipelines need preparing.
    auto* gate = new FritchiiUi::PrecompileGate(
        this, statusBar(),
        {.pause =
             [this] {
                 LOG_INFO(Frontend, "Pausing: shader preparation");
                 OnPauseGame();
             },
         .resume = [this] { OnStartGame(); },
         .game_name = [] {
             return QtCommon::system &&
                            QtCommon::system->GetApplicationProcessProgramID() == OcarinaOfTime
                        ? QStringLiteral("OoT")
                        : tr("the game");
         },
         .missing_shader_setup = [this, show_shader_setup] {
             if (emulation_running &&
                 QtCommon::system->GetApplicationProcessProgramID() == OcarinaOfTime &&
                 !UISettings::values.fritchii_shader_setup_seen.GetValue()) {
                 show_shader_setup(true);
             }
         }});
    connect(this, &MainWindow::EmulationStarting, gate,
            &FritchiiUi::PrecompileGate::OnEmulationStarting);
    connect(this, &MainWindow::EmulationStopping, gate,
            &FritchiiUi::PrecompileGate::OnEmulationStopping);
}
