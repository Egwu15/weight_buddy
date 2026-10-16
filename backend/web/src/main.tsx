import { hydrateRoot } from "react-dom/client";

import { App } from "./app";
import { routeFromPath } from "./routes";
import "./styles.css";

// The pages are pre-rendered, so this only hydrates the existing markup. With
// JavaScript disabled the HTML still reads completely.
const container = document.getElementById("root");
if (container) {
  hydrateRoot(
    container,
    <App route={routeFromPath(window.location.pathname)} />,
  );
}
