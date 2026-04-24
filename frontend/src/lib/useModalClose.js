import { useCallback, useState } from 'react'

const EXIT_MS = 260

export function useModalClose(onClose) {
  const [closing, setClosing] = useState(false)

  const requestClose = useCallback(() => {
    if (closing) return
    setClosing(true)
    setTimeout(onClose, EXIT_MS)
  }, [closing, onClose])

  return { closing, requestClose }
}
