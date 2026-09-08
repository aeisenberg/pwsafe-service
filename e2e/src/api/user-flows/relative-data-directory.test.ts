import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { ApiClient } from "../../helpers/api-client";
import { ServerInstance } from "../../helpers/server";

describe("Relative data directory", { timeout: 30_000 }, () => {
  let server: ServerInstance;
  let api: ApiClient;

  beforeAll(async () => {
    server = new ServerInstance({ relativePaths: true });
    await server.start();
    api = new ApiClient(server.baseUrl, server.csrfToken);

    const { url } = await api.getProviderAuthUrl("mock");
    await api.raw("GET", url.replace(server.baseUrl, ""));
  });

  afterAll(async () => {
    await server.stop();
  });

  it("persists provider selections repeatedly and syncs them", async () => {
    const { files } = await api.getProviderFiles("mock");
    const selected = files.map((file) => ({ ...file, selected: true }));

    expect(await api.saveProviderFiles("mock", selected)).toEqual({ success: true });
    expect(await api.saveProviderFiles("mock", selected)).toEqual({ success: true });

    const { results } = await api.syncProvider("mock");
    expect(results.length).toBeGreaterThan(0);
    expect(results.every((result) => result.success)).toBe(true);

    const safes = await api.listSafes();
    expect(safes.filter((safe) => safe.provider === "mock").length).toBe(files.length);
  });
});
