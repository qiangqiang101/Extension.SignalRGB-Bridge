type Translations = Record<string, string>

const I18N: Record<string, Translations> = {
  'en-US': {
    title: 'Script Manager',
    connected: 'Connected',
    disconnected: 'Disconnected',
    rescan: 'Rescan',
    filter_all: 'All',
    filter_loaded: 'Loaded',
    filter_error: 'Error',
    filter_disabled: 'Disabled',
    loading: 'Loading\u2026',
    no_scripts: 'No scripts found',
    no_match: 'No scripts match this filter',
    stats: '{total} scripts \u00b7 {ok} loaded \u00b7 {err} errors \u00b7 {dis} disabled',
    vid: 'VID',
    has_devices: 'Active Devices',
    error_label: 'Error',
    publisher: 'by {pub}',
  },
  'zh-CN': {
    title: '\u811a\u672c\u7ba1\u7406',
    connected: '\u5df2\u8fde\u63a5',
    disconnected: '\u672a\u8fde\u63a5',
    rescan: '\u91cd\u65b0\u626b\u63cf',
    filter_all: '\u5168\u90e8',
    filter_loaded: '\u5df2\u52a0\u8f7d',
    filter_error: '\u9519\u8bef',
    filter_disabled: '\u5df2\u7981\u7528',
    loading: '\u52a0\u8f7d\u4e2d\u2026',
    no_scripts: '\u672a\u627e\u5230\u811a\u672c',
    no_match: '\u6ca1\u6709\u5339\u914d\u7684\u811a\u672c',
    stats: '{total} \u4e2a\u811a\u672c \u00b7 {ok} \u5df2\u52a0\u8f7d \u00b7 {err} \u9519\u8bef \u00b7 {dis} \u5df2\u7981\u7528',
    vid: 'VID',
    has_devices: '\u6d3b\u52a8\u8bbe\u5907',
    error_label: '\u9519\u8bef',
    publisher: '\u6765\u81ea {pub}',
  },
  'zh-TW': {
    title: '\u8173\u672c\u7ba1\u7406',
    connected: '\u5df2\u9023\u63a5',
    disconnected: '\u672a\u9023\u63a5',
    rescan: '\u91cd\u65b0\u6383\u63cf',
    filter_all: '\u5168\u90e8',
    filter_loaded: '\u5df2\u8f09\u5165',
    filter_error: '\u932f\u8aa4',
    filter_disabled: '\u5df2\u505c\u7528',
    loading: '\u8f09\u5165\u4e2d\u2026',
    no_scripts: '\u672a\u627e\u5230\u8173\u672c',
    no_match: '\u6c92\u6709\u5339\u914d\u7684\u8173\u672c',
    stats: '{total} \u500b\u8173\u672c \u00b7 {ok} \u5df2\u8f09\u5165 \u00b7 {err} \u932f\u8aa4 \u00b7 {dis} \u5df2\u505c\u7528',
    vid: 'VID',
    has_devices: '\u6d3b\u52d5\u88dd\u7f6e',
    error_label: '\u932f\u8aa4',
    publisher: '\u4f86\u81ea {pub}',
  },
  'ru': {
    title: 'Менеджер скриптов',
    connected: 'Подключено',
    disconnected: 'Отключено',
    rescan: 'Повторное сканирование',
    filter_all: 'Все',
    filter_loaded: 'Загружены',
    filter_error: 'Ошибки',
    filter_disabled: 'Отключены',
    loading: 'Загрузка…',
    no_scripts: 'Скрипты не найдены',
    no_match: 'Нет скриптов, соответствующих фильтру',
    stats: '{total} скриптов · {ok} загружено · {err} ошибок · {dis} отключено',
    vid: 'VID',
    has_devices: 'Активные устройства',
    error_label: 'Ошибка',
    publisher: 'от {pub}',
  },
  'tr': {
    title: 'Komut Dosyası Yöneticisi',
    connected: 'Bağlı',
    disconnected: 'Bağlantı Kesildi',
    rescan: 'Yeniden Tara',
    filter_all: 'Tümü',
    filter_loaded: 'Yüklendi',
    filter_error: 'Hata',
    filter_disabled: 'Devre Dışı',
    loading: 'Yükleniyor…',
    no_scripts: 'Komut dosyası bulunamadı',
    no_match: 'Bu filtreyle eşleşen komut dosyası yok',
    stats: '{total} komut dosyası · {ok} yüklendi · {err} hata · {dis} devre dışı',
    vid: 'VID',
    has_devices: 'Etkin Cihazlar',
    error_label: 'Hata',
    publisher: '{pub} tarafından',
  },
}

let currentLocale = window.__SKYDIMO_EXT_PAGE__?.locale ?? 'en-US'
const localeListeners = new Set<(locale: string) => void>()

export function setLocale(locale: string) {
  currentLocale = locale
  for (const listener of localeListeners) {
    listener(locale)
  }
}

export function getLocale() {
  return currentLocale
}

export function onLocaleChange(listener: (locale: string) => void) {
  localeListeners.add(listener)
  return () => localeListeners.delete(listener)
}

export function t(key: string, vars?: Record<string, string | number>): string {
  const lang = I18N[currentLocale] ?? I18N['en-US']
  let str = lang[key] ?? I18N['en-US'][key] ?? key
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      str = str.replace(`{${k}}`, String(v))
    }
  }
  return str
}
