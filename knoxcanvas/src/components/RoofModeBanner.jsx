import { useApp } from '../context/AppContext';

export default function RoofModeBanner() {
  const { mapUi } = useApp();
  return (
    <div id="roof-mode-banner" className={mapUi.roofingMode ? 'show' : ''}>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /></svg>
      Roofing Target Mode — zones built before 2012
    </div>
  );
}
