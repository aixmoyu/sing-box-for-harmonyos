import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { writeFully } from '../domain/CompleteWrite'

export async function installBuiltinRules(context: common.UIAbilityContext): Promise<string> {
  const directory: string = context.filesDir + '/builtin-rules-v1'
  if (!await fileIo.access(directory)) await fileIo.mkdir(directory, true)
  for (const name of ['cn.srs', 'geoip-cn.srs', 'gfw.srs']) {
    const path: string = directory + '/' + name
    // Keep rule-sets refreshed at runtime; only seed missing files.
    if (await fileIo.access(path)) continue
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent('builtin-rules/' + name)
    const candidate: string = path + '.candidate'
    const file: fileIo.File = await fileIo.open(candidate, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    try {
      await writeFully(bytes, async (chunk: ArrayBuffer): Promise<number> => await fileIo.write(file.fd, chunk))
      await fileIo.fsync(file.fd)
    } finally { await fileIo.close(file) }
    await fileIo.rename(candidate, path)
  }
  return directory
}
