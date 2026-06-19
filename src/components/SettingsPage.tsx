type Theme = 'light' | 'dark'

interface SettingsPageProps {
  theme: Theme
  onToggleTheme: () => void
  comic: boolean
  onToggleComic: () => void
}

export default function SettingsPage({ theme, onToggleTheme, comic, onToggleComic }: SettingsPageProps) {
  return (
    <div className="settings-page">
      <div className="settings-header">
        <h2>Settings</h2>
      </div>

      <section className="settings-section">
        <h3 className="settings-section-title">Design</h3>

        <div className="settings-row">
          <div className="settings-row-text">
            <span className="settings-row-label">Appearance</span>
            <span className="settings-row-desc">Switch between light and dark color schemes.</span>
          </div>
          <button
            type="button"
            className={`settings-switch ${theme === 'dark' ? 'on' : ''}`}
            role="switch"
            aria-checked={theme === 'dark'}
            onClick={onToggleTheme}
          >
            <span className="settings-switch-track">
              <span className="settings-switch-thumb" />
            </span>
            <span className="settings-switch-value">{theme === 'dark' ? 'Dark' : 'Light'}</span>
          </button>
        </div>

        <div className="settings-row">
          <div className="settings-row-text">
            <span className="settings-row-label">Comic style ✨</span>
            <span className="settings-row-desc">
              Turn everything colorful and cartoon-style. Comic fonts, rainbow background and bouncy buttons.
            </span>
          </div>
          <button
            type="button"
            className={`settings-switch ${comic ? 'on' : ''}`}
            role="switch"
            aria-checked={comic}
            onClick={onToggleComic}
          >
            <span className="settings-switch-track">
              <span className="settings-switch-thumb" />
            </span>
            <span className="settings-switch-value">{comic ? 'On' : 'Off'}</span>
          </button>
        </div>
      </section>
    </div>
  )
}
