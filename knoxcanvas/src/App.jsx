import { lazy, Suspense, useEffect, useState } from 'react';
import { useApp } from './context/AppContext';
import AuthScreen from './components/AuthScreen';
import SetupScreen from './components/SetupScreen';
import Header from './components/Header';
import SearchBar from './components/SearchBar';
import MapView from './components/MapView';
import PinSheet from './components/PinSheet';
import Legend from './components/Legend';
import RoofModeBanner from './components/RoofModeBanner';
import QuickTapBanner from './components/QuickTapBanner';
import ZipWidget from './components/ZipWidget';
import ZoneToolbar from './components/ZoneToolbar';
import ShiftsPanel from './components/panels/ShiftsPanel';
import Toast from './components/Toast';

const RoutePanel = lazy(() => import('./components/panels/RoutePanel'));
const ExportPanel = lazy(() => import('./components/panels/ExportPanel'));
const MetricsPanel = lazy(() => import('./components/panels/MetricsPanel'));
const AdminPanel = lazy(() => import('./components/AdminPanel'));

export default function App() {
  const { authReady, currentUser, currentUserProfile, companyId, mapUi } = useApp();
  const { activePanel, adminOpen } = mapUi || {};

  // Panels are only fetched once actually needed, then stay mounted so the
  // usual slide-in CSS transition still plays on subsequent opens/closes.
  const [everOpened, setEverOpened] = useState({ route: false, export: false, metrics: false, admin: false });
  useEffect(() => {
    if (!activePanel && !adminOpen) return;
    setEverOpened((prev) => ({
      route: prev.route || activePanel === 'route',
      export: prev.export || activePanel === 'export',
      metrics: prev.metrics || activePanel === 'metrics',
      admin: prev.admin || !!adminOpen,
    }));
  }, [activePanel, adminOpen]);

  if (!authReady) return null;

  if (!currentUser) {
    return (
      <>
        <AuthScreen />
        <Toast />
      </>
    );
  }

  if (!currentUserProfile || !companyId) {
    return (
      <>
        <SetupScreen />
        <Toast />
      </>
    );
  }

  return (
    <>
      <div id="app-root" style={{ display: 'block' }}>
        <MapView />
        <Header />
        <SearchBar />
        <PinSheet />
        <Legend />
        <RoofModeBanner />
        <QuickTapBanner />
        <ZipWidget />
        <ZoneToolbar />
        <ShiftsPanel />
        <Suspense fallback={null}>
          {everOpened.route && <RoutePanel />}
          {everOpened.export && <ExportPanel />}
        </Suspense>
      </div>
      <Suspense fallback={null}>
        {everOpened.metrics && <MetricsPanel />}
        {everOpened.admin && <AdminPanel />}
      </Suspense>
      <Toast />
    </>
  );
}
