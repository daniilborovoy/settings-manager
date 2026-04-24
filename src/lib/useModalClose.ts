import { useCallback, useEffect, useState } from 'react'

const EXIT_MS = 260

export function useModalClose(onClose: () => void) {
  const [closing, setClosing] = useState(false)

  const requestClose = useCallback(() => {
    if (closing) return
    setClosing(true)
    window.setTimeout(onClose, EXIT_MS)
  }, [closing, onClose])

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') requestClose()
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [requestClose])

  return { closing, requestClose }
}
