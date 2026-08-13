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
import RoutePanel from './components/panels/RoutePanel';
import ExportPanel from './components/panels/ExportPanel';
import MetricsPanel from './components/panels/MetricsPanel';
import AdminPanel from './components/AdminPanel';
import Toast from './components/Toast';

export default function App() {
  const { authReady, currentUser, currentUserProfile, companyId } = useApp();

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
        <RoutePanel />
        <ExportPanel />
      </div>
      <MetricsPanel />
      <AdminPanel />
      <Toast />
    </>
  );
}
