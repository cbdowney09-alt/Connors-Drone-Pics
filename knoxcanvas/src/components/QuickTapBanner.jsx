import { useApp } from '../context/AppContext';
import { COLORS, LABELS } from '../constants';

export default function QuickTapBanner() {
  const { mapUi } = useApp();
  const { quickTapStatus, setQuickTapStatus } = mapUi;

  if (!quickTapStatus) return null;

  return (
    <div id="quicktap-banner" style={{ background: COLORS[quickTapStatus] }} onClick={() => setQuickTapStatus(null)}>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" /></svg>
      Quick tap: {LABELS[quickTapStatus]} — tap the map to mark · tap here to stop
    </div>
  );
}
