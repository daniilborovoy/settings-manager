//! Application-level error type serialized across the Tauri IPC boundary.

use crate::providers::ProviderError;

/// Top-level error returned by every Tauri command.
///
/// Serialized as its `Display` string because the frontend only consumes
/// human-readable messages (and matches on substrings like `401`).
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("DB error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error(transparent)]
    Provider(#[from] ProviderError),
    #[error("{0} not found")]
    NotFound(&'static str),
    #[error("Source is not a GitLab CI/CD source")]
    NotGitlabSource,
    #[error("Source config is malformed")]
    MalformedConfig,
    #[error("Internal state lock poisoned")]
    LockPoisoned,
}

impl serde::Serialize for AppError {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}
