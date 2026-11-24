import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const [output] = process.argv.slice(2);
if (!output) throw new Error("Expected a destination Info.plist");

const feed = process.env.UPDATE_FEED_URL || "";
const key = process.env.UPDATE_PUBLIC_KEY || "";
if (feed || key) {
    if (!URL.canParse(feed) || new URL(feed).protocol !== "https:") {
        throw new Error("Set UPDATE_FEED_URL to an HTTPS appcast URL");
    }
    const bytes = Buffer.from(key, "base64");
    if (bytes.length !== 32 || bytes.toString("base64") !== key) {
        throw new Error("Set UPDATE_PUBLIC_KEY to a base64-encoded Sparkle Ed25519 public key");
    }
}

const { version, build } = JSON.parse(readFileSync(new URL("./version.json", import.meta.url), "utf8"));
if (typeof version !== "string" || !/^\d+\.\d+\.\d+$/.test(version) || !Number.isSafeInteger(build) || build < 1) {
    throw new Error("Expected a release version and positive build number in version.json");
}
const info = JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", "Info.plist"], { encoding: "utf8" }));
info.CFBundleShortVersionString = version;
info.CFBundleVersion = String(build);
if (feed) {
    info.SUFeedURL = feed;
    info.SUPublicEDKey = key;
}
execFileSync("plutil", ["-convert", "xml1", "-o", output, "--", "-"], { input: JSON.stringify(info) });
