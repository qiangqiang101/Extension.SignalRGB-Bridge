import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Box, Flex, Text, Switch, Badge, Spinner, Icon, IconButton, Input } from '@chakra-ui/react'
import { RefreshCw, FileCode2, CheckCircle2, XCircle, Ban, Monitor, AlertTriangle } from 'lucide-react'
import { bridge, type ConnectionStatus, type BridgeEvent } from './bridge'
import type { ScriptInfo } from './types'
import { t, onLocaleChange } from './i18n'

type Filter = 'all' | 'ok' | 'error' | 'disabled'

function useForceUpdate() {
  const [, setState] = useState(0)
  return useCallback(() => setState((n) => n + 1), [])
}

function useBridge() {
  const [scripts, setScripts] = useState<ScriptInfo[]>([])
  const [status, setStatus] = useState<ConnectionStatus>('disconnected')
  const forceUpdate = useForceUpdate()

  useEffect(() => {
    const unsubEvent = bridge.subscribe((event: BridgeEvent) => {
      if (event.type === 'scripts_snapshot') {
        setScripts(event.data.scripts)
      }
    })
    const unsubStatus = bridge.subscribeStatus(setStatus)
    const unsubLocale = onLocaleChange(() => forceUpdate())
    bridge.connect()
    return () => {
      unsubEvent()
      unsubStatus()
      unsubLocale()
      bridge.disconnect()
    }
  }, [forceUpdate])

  return { scripts, status }
}

function StatusBadge({ status }: { status: ConnectionStatus }) {
  const connected = status === 'connected'
  return (
    <Badge
      px="2.5"
      py="0.5"
      borderRadius="var(--radius-l)"
      fontSize="xs"
      fontWeight="500"
      bg={connected ? 'var(--badge-ok-bg)' : 'var(--badge-error-bg)'}
      color={connected ? 'var(--badge-ok-text)' : 'var(--badge-error-text)'}
    >
      <Box
        as="span"
        display="inline-block"
        w="6px"
        h="6px"
        borderRadius="full"
        bg={connected ? 'var(--badge-ok-text)' : 'var(--badge-error-text)'}
        mr="1.5"
      />
      {connected ? t('connected') : t('disconnected')}
    </Badge>
  )
}

function FilterBar({ filter, onFilter, counts }: {
  filter: Filter
  onFilter: (f: Filter) => void
  counts: Record<Filter, number>
}) {
  const filters: Filter[] = ['all', 'ok', 'error', 'disabled']
  const labels: Record<Filter, string> = {
    all: t('filter_all'),
    ok: t('filter_loaded'),
    error: t('filter_error'),
    disabled: t('filter_disabled'),
  }

  return (
    <Flex gap="1.5" flexWrap="wrap">
      {filters.map((f) => {
        const active = filter === f
        return (
          <Box
            key={f}
            as="button"
            px="3"
            py="1"
            fontSize="13px"
            fontWeight="500"
            borderRadius="var(--radius-l)"
            cursor="pointer"
            transition="all 0.15s"
            border="1px solid"
            borderColor={active ? 'var(--accent-color)' : 'var(--border-subtle)'}
            bg={active ? 'var(--accent-color)' : 'transparent'}
            color={active ? 'var(--accent-text)' : 'var(--text-secondary)'}
            _hover={{
              bg: active ? 'var(--accent-hover)' : 'var(--bg-card-hover)',
            }}
            onClick={() => onFilter(f)}
          >
            {labels[f]} ({counts[f]})
          </Box>
        )
      })}
    </Flex>
  )
}

function ScriptStatusIcon({ script }: { script: ScriptInfo }) {
  if (script.disabled) {
    return <Icon color="var(--text-muted)" boxSize="18px"><Ban size={18} /></Icon>
  }
  if (script.status === 'error') {
    return <Icon color="var(--color-error)" boxSize="18px"><XCircle size={18} /></Icon>
  }
  return <Icon color="var(--color-success)" boxSize="18px"><CheckCircle2 size={18} /></Icon>
}

function ScriptCard({ script, onToggle }: {
  script: ScriptInfo
  onToggle: (path: string, disabled: boolean) => void
}) {
  const fileName = script.path.split(/[/\\]/).pop() ?? script.path
  const [showError, setShowError] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (showError && inputRef.current) {
      inputRef.current.focus()
      inputRef.current.select()
    }
  }, [showError])

  return (
    <Flex
      bg="var(--bg-card)"
      borderRadius="var(--radius-m)"
      border="1px solid var(--border-subtle)"
      p="3.5"
      gap="3"
      align="center"
      transition="all 0.15s"
      opacity={script.disabled ? 0.55 : 1}
      _hover={{
        bg: 'var(--bg-card-hover)',
        borderColor: 'var(--border-strong)',
      }}
    >
      <Flex
        align="center"
        justify="center"
        w="36px"
        h="36px"
        minW="36px"
        borderRadius="var(--radius-m)"
        bg="var(--card-icon-bg)"
      >
        <ScriptStatusIcon script={script} />
      </Flex>

      <Box flex="1" minW="0">
        <Text fontSize="13.5px" fontWeight="600" color="var(--text-primary)" truncate>
          {script.name}
        </Text>
        <Flex gap="1.5" mt="1" flexWrap="wrap" align="center">
          <Text fontSize="11.5px" color="var(--text-muted)" truncate>
            {fileName}
          </Text>
          {script.publisher && (
            <Text fontSize="11.5px" color="var(--text-muted)">
              · {t('publisher', { pub: script.publisher })}
            </Text>
          )}
        </Flex>

        <Flex gap="1.5" mt="1.5" flexWrap="wrap">
          {script.vid && (
            <Badge
              fontSize="10.5px"
              px="1.5"
              py="0"
              borderRadius="var(--radius-s)"
              bg="var(--badge-device-bg)"
              color="var(--badge-device-text)"
              fontWeight="500"
            >
              {t('vid')}: {script.vid}
            </Badge>
          )}
          {script.device_type && (
            <Badge
              fontSize="10.5px"
              px="1.5"
              py="0"
              borderRadius="var(--radius-s)"
              bg="var(--badge-device-bg)"
              color="var(--badge-device-text)"
              fontWeight="500"
            >
              {script.device_type}
            </Badge>
          )}
          {script.has_devices && (
            <Badge
              fontSize="10.5px"
              px="1.5"
              py="0"
              borderRadius="var(--radius-s)"
              bg="var(--badge-ok-bg)"
              color="var(--badge-ok-text)"
              fontWeight="500"
            >
              <Icon mr="0.5" boxSize="11px"><Monitor size={11} /></Icon>
              {t('has_devices')}
            </Badge>
          )}
        </Flex>
      </Box>

      {script.status === 'error' && script.error_message ? (
        <Flex align="center" gap="1.5" minW="0" flex={showError ? 1 : undefined}>
          {showError && (
            <Input
              ref={inputRef}
              readOnly
              value={script.error_message}
              size="xs"
              fontSize="11.5px"
              color="var(--color-error)"
              bg="var(--bg-app)"
              border="1px solid var(--border-subtle)"
              borderRadius="var(--radius-s)"
              px="2"
              h="28px"
              flex="1"
              minW="0"
              _focus={{ borderColor: 'var(--color-error)', outline: 'none' }}
              onBlur={() => setShowError(false)}
            />
          )}
          <IconButton
            aria-label={script.error_message}
            size="xs"
            variant="ghost"
            borderRadius="var(--radius-s)"
            color="var(--color-error)"
            minW="28px"
            h="28px"
            _hover={{ bg: 'var(--badge-error-bg)' }}
            onClick={() => setShowError((v) => !v)}
          >
            <AlertTriangle size={16} />
          </IconButton>
        </Flex>
      ) : (
        <Switch.Root
          checked={!script.disabled}
          onCheckedChange={(details) => onToggle(script.path, !details.checked)}
        >
          <Switch.HiddenInput />
          <Switch.Control>
            <Switch.Thumb />
          </Switch.Control>
        </Switch.Root>
      )}
    </Flex>
  )
}

export default function App() {
  const { scripts, status } = useBridge()
  const [filter, setFilter] = useState<Filter>('all')

  const counts = useMemo(() => {
    const c: Record<Filter, number> = { all: 0, ok: 0, error: 0, disabled: 0 }
    for (const s of scripts) {
      c.all++
      if (s.disabled) c.disabled++
      else if (s.status === 'error') c.error++
      else c.ok++
    }
    return c
  }, [scripts])

  const filtered = useMemo(() => {
    const list = scripts.filter((s) => {
      switch (filter) {
        case 'ok': return s.status === 'ok' && !s.disabled
        case 'error': return s.status === 'error'
        case 'disabled': return !!s.disabled
        default: return true
      }
    })
    list.sort((a, b) => (b.has_devices ? 1 : 0) - (a.has_devices ? 1 : 0))
    return list
  }, [scripts, filter])

  const handleToggle = useCallback((path: string, disabled: boolean) => {
    bridge.send('toggle_script', { path, disabled })
  }, [])

  const handleRescan = useCallback(() => {
    bridge.send('rescan')
  }, [])

  const hasData = scripts.length > 0

  return (
    <Flex direction="column" h="100%" maxH="100vh" overflow="hidden">
      {/* Header */}
      <Box
        px="5"
        pt="4"
        pb="3"
        borderBottom="1px solid var(--border-subtle)"
        bg="var(--bg-panel)"
        position="sticky"
        top="0"
        zIndex="10"
      >
        <Flex align="center" justify="space-between" mb="3">
          <Flex align="center" gap="3">
            <Icon boxSize="20px" color="var(--accent-color)">
              <FileCode2 size={20} />
            </Icon>
            <Text fontSize="16px" fontWeight="700" color="var(--text-primary)">
              {t('title')}
            </Text>
            <StatusBadge status={status} />
          </Flex>

          <Box
            as="button"
            display="flex"
            alignItems="center"
            gap="1.5"
            px="2.5"
            py="1"
            fontSize="13px"
            fontWeight="500"
            borderRadius="var(--radius-m)"
            border="1px solid var(--border-subtle)"
            bg="transparent"
            color="var(--text-secondary)"
            cursor="pointer"
            transition="all 0.15s"
            _hover={{ bg: 'var(--bg-card-hover)', color: 'var(--accent-color)', borderColor: 'var(--accent-color)' }}
            onClick={handleRescan}
          >
            <RefreshCw size={14} />
            {t('rescan')}
          </Box>
        </Flex>

        {hasData && (
          <>
            <Text fontSize="12px" color="var(--text-muted)" mb="2.5">
              {t('stats', {
                total: counts.all,
                ok: counts.ok,
                err: counts.error,
                dis: counts.disabled,
              })}
            </Text>
            <FilterBar filter={filter} onFilter={setFilter} counts={counts} />
          </>
        )}
      </Box>

      {/* Content */}
      <Box flex="1" overflow="auto" px="5" py="3">
        {!hasData ? (
          <Flex align="center" justify="center" h="100%" direction="column" gap="3">
            {status === 'connected' ? (
              <Spinner size="md" color="var(--accent-color)" />
            ) : (
              <Text fontSize="13px" color="var(--text-muted)">{t('loading')}</Text>
            )}
          </Flex>
        ) : filtered.length === 0 ? (
          <Flex align="center" justify="center" h="100px">
            <Text fontSize="13px" color="var(--text-muted)">{t('no_match')}</Text>
          </Flex>
        ) : (
          <Flex direction="column" gap="2">
            {filtered.map((script) => (
              <ScriptCard key={script.path} script={script} onToggle={handleToggle} />
            ))}
          </Flex>
        )}
      </Box>
    </Flex>
  )
}
