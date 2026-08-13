import { useCallback, useRef, useState } from 'react';

export function useToast() {
  const [toast, setToast] = useState({ msg: '', show: false });
  const timerRef = useRef(null);

  const showToast = useCallback((msg) => {
    clearTimeout(timerRef.current);
    setToast({ msg, show: true });
    timerRef.current = setTimeout(() => setToast((t) => ({ ...t, show: false })), 2000);
  }, []);

  return { toast, showToast };
}
