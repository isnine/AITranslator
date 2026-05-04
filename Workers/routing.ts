export function normalizeApiPath(path: string): string {
  if (path === "/api" || path === "/api/") {
    return "/";
  }
  if (path.startsWith("/api/")) {
    return path.slice(4);
  }
  return path;
}
