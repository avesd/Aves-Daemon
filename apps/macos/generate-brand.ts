import { BIRD_VIEW_BOX, getLogoGeometry } from "@avesd/logo/geometry";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import svgpath from "svgpath";

const point = (x: number, y: number) => `CGPoint(x: ${x}, y: ${y})`;

function drawingCommands(data: string): string {
    const path = svgpath(data).abs().unshort().unarc();
    const lines: string[] = [];
    path.iterate(([command, ...p]) => {
        let call: string;
        switch (command) {
            case "M": call = `move(to: ${point(p[0], p[1])})`; break;
            case "L": call = `addLine(to: ${point(p[0], p[1])})`; break;
            case "C":
                call = `addCurve(to: ${point(p[4], p[5])}, control1: ${point(p[0], p[1])}, control2: ${point(p[2], p[3])})`;
                break;
            case "Z": call = "closeSubpath()"; break;
            default: throw new Error(`Unsupported brand path command: ${command}`);
        }
        lines.push(`        path.${call}`);
    });
    return lines.join("\n");
}


const [x, y, width, height] = BIRD_VIEW_BOX.split(" ").map(Number);
if (x !== 0 || y !== 0 || width !== height) {
    throw new Error("Review the updated brand viewport before generating the native mark.");
}

function variant(name: "square" | "standard"): string {
    const mark = getLogoGeometry(name);
    if (!mark.path.startsWith(mark.contour)) throw new Error(`Unexpected compound path for ${name}`);
    return `    static let ${name} = Mark(contour: Path { path in
${drawingCommands(mark.contour)}
    }, eye: Path { path in
${drawingCommands(mark.path.slice(mark.contour.length))}
    })`;
}

const swift = `// Generated from @avesd/logo by generate-brand.ts.
import SwiftUI

enum BrandGeometry {
    struct Mark {
        let contour: Path
        let eye: Path

        var solid: Path {
            var path = contour
            path.addPath(eye)
            return path
        }
    }

    static let size: CGFloat = ${width}
${variant("square")}

${variant("standard")}
}
`;
const output = new URL("./Sources/AvesdOverlay/BrandGeometry.swift", import.meta.url);
if (!existsSync(output) || readFileSync(output, "utf8") !== swift) {
    writeFileSync(output, swift);
}
