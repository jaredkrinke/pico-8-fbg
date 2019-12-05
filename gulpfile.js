const { series, parallel, src, dest } = require("gulp");
const del = require("del");
const minifyJS = require("gulp-uglify");
const minifyHTML = require("gulp-htmlmin");

function clean() {
    return del("output");
}

function html(cb) {
    return src("*.html")
        .pipe(minifyHTML({
            collapseWhitespace: true,
            removeComments: true,
            minifyCSS: true,
            minifyJS: true,
        }))
        .pipe(dest("output/"));
}

function copy(cb) {
    // No minifying since this is probably asm.js anyway
    return src("fbg.js")
        .pipe(dest("output/"));
}

function javascript(cb) {
    return src(["comm.js", "logic.js"])
        .pipe(minifyJS())
        .pipe(dest("output/"));
}

const bundle = series(clean, parallel(html, javascript, copy));

exports.default = bundle;
