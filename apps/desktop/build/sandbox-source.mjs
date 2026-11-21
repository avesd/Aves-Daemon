/**
 * @author Avesd
 * @package Desktop
 * @namespace Build
 * @description Compile browser-only sandbox entries for inline documents
 */

import { stripTypeScriptTypes } from "node:module";

export function sandboxSource(source) {

    return stripTypeScriptTypes(source, { mode: "transform" }).replace(/<\/script/giu, "<\\/script");
}
