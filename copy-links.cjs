// Hvigor's bundled wrapper creates directory symlinks. On Windows without
// symlink privileges, stage physical copies in the build cache instead.
const fs = require('fs');
const path = require('path');
function copyLink(src, dst) {
  const resolved = path.isAbsolute(src) ? src : path.resolve(path.dirname(dst), src);
  if (fs.existsSync(dst)) return;
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.cpSync(resolved, dst, { recursive: true, dereference: true });
}
fs.symlinkSync = copyLink;
fs.promises.symlink = async (src, dst) => copyLink(src, dst);
fs.symlink = (src, dst, type, cb) => {
  const callback = typeof type === 'function' ? type : cb;
  try { copyLink(src, dst); callback(null); } catch (err) { callback(err); }
};
