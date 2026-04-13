export interface ScriptInfo {
  name: string
  path: string
  status: 'ok' | 'error'
  disabled: boolean
  vid?: string
  device_type?: string
  publisher?: string
  has_devices?: boolean
  error_message?: string
}

export interface ScriptsSnapshotPayload {
  scripts: ScriptInfo[]
}
