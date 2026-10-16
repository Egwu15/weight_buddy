import { Layout } from "./components/Layout";
import { DeleteAccount } from "./pages/DeleteAccount";
import { Home } from "./pages/Home";
import { NotFound } from "./pages/NotFound";
import { Privacy } from "./pages/Privacy";
import { Terms } from "./pages/Terms";
import type { RouteKey } from "./routes";

/** The whole site. The route is passed in so pre-render and hydration agree. */
export function App({ route }: { route: RouteKey }) {
  return <Layout route={route}>{renderPage(route)}</Layout>;
}

function renderPage(route: RouteKey) {
  switch (route) {
    case "privacy":
      return <Privacy />;
    case "terms":
      return <Terms />;
    case "delete-account":
      return <DeleteAccount />;
    case "not-found":
      return <NotFound />;
    case "home":
    default:
      return <Home />;
  }
}
