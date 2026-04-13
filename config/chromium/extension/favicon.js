const favicon = document.getElementById("favicon");
const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");

function updateFavicon() {
  favicon.href = colorScheme.matches ? "favicon-dark.svg" : "favicon-light.svg";
}

colorScheme.addEventListener("change", updateFavicon);
updateFavicon();
