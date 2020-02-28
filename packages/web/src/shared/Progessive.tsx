import { useRouter } from 'next/router'
import * as React from 'react'
import { StyleSheet, View } from 'react-native'
import { colors } from 'src/styles'
import { EffectiveTypes, getEffectiveConnection } from 'src/utils/utils'

// https://nextjs.org/docs/api-reference/next/router#router-api
enum RouterEvents {
  routeChangeStart = 'routeChangeStart',
  routeChangeComplete = 'routeChangeComplete',
  routeChangeError = 'routeChangeError',
}

export function usePageTurner() {
  const router = useRouter()
  const [isPageTurning, setPageTurning] = React.useState(false)
  const [hasError, setError] = React.useState(false)
  React.useEffect(() => {
    router.events.on(RouterEvents.routeChangeStart, () => {
      setPageTurning(true)
      setError(false)
    })
    router.events.on(RouterEvents.routeChangeComplete, () => {
      setPageTurning(false)
      setError(false)
    })
    router.events.on(RouterEvents.routeChangeError, (error, url) => {
      if (error.cancelled) {
        // TODO a way to show rerouting
        console.log('rerouting', url)
      }
      setError(true)
    })
  }, [])

  return [isPageTurning, hasError]
}

export default function Progressive() {
  const [isPageTurning, error] = usePageTurner()

  if (isPageTurning) {
    const speed = getEffectiveConnection(navigator)
    const animationSpeed = styles[speed]
    return (
      <View style={styles.container}>
        <View style={[styles.bar, animationSpeed, error ? styles.bad : styles.good]} />
      </View>
    )
  }
  return null
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    zIndex: 1000,
    height: 2,
    width: '100%',
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
  },
  [EffectiveTypes['slow-2g']]: {
    animationDuration: `35s`,
  },
  [EffectiveTypes['2g']]: {
    animationDuration: `20s`,
  },
  [EffectiveTypes.unknown]: {
    animationDuration: `15s`,
  },
  [EffectiveTypes['3g']]: {
    animationDuration: `15s`,
  },
  [EffectiveTypes['4g']]: {
    animationDuration: `8s`,
  },
  good: {
    backgroundColor: colors.primary,
  },
  bad: {
    backgroundColor: colors.red,
  },
  bar: {
    transformProperty: 'background-color',
    transformDuration: '1s',
    height: '100%',
    width: '100%',
    transformOrigin: 'left',
    animationFillMode: 'both',
    animationTimingFunction: 'cubic-bezier(0,.58,.51,1.01)',
    animationKeyframes: [
      {
        '0%': {
          transform: [{ scaleX: 0 }],
        },

        '100%': {
          transform: [{ scaleX: 1 }],
        },
      },
    ],
  },
})