#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod db;
mod providers;

use std::sync::Mutex;

use tauri::Manager;

use commands::AppState;

const APP_DISPLAY_NAME: &str = "Settings Manager";

#[cfg(target_os = "macos")]
fn set_macos_process_name() {
    use objc2::msg_send;
    use objc2::runtime::{AnyClass, AnyObject};
    use objc2_foundation::NSString;

    unsafe {
        let Some(cls) = AnyClass::get("NSProcessInfo") else { return };
        let process_info: *mut AnyObject = msg_send![cls, processInfo];
        if process_info.is_null() {
            return;
        }
        let name = NSString::from_str(APP_DISPLAY_NAME);
        let _: () = msg_send![process_info, setProcessName: &*name];
    }
}

fn main() {
    #[cfg(target_os = "macos")]
    set_macos_process_name();

    tauri::Builder::default()
        .setup(|app| {
            let app_dir = app
                .path()
                .app_data_dir()
                .expect("failed to resolve app data dir");
            std::fs::create_dir_all(&app_dir).expect("failed to create app data dir");
            let db_path = app_dir.join("settings_manager.db");
            let conn = db::open(&db_path).expect("failed to open sqlite db");
            app.manage(AppState {
                db: Mutex::new(conn),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_projects_with_sources,
            commands::create_project,
            commands::rename_project,
            commands::delete_project,
            commands::reorder_projects,
            commands::create_source,
            commands::rename_source,
            commands::delete_source,
            commands::reorder_sources,
            commands::get_variables,
            commands::save_variables,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
