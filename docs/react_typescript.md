# @types/react

The @types/react package provides comprehensive TypeScript type definitions for React. It enables full type safety when using React with TypeScript, covering all React APIs including components, hooks, events, and JSX elements. The package supports multiple entry points for different React features and release channels.

## Package Information

- **Package Name**: @types/react
- **Package Type**: npm
- **Language**: TypeScript
- **Installation**: `npm install @types/react`

## Core Imports

```typescript
import React from "react";
```

For specific features:

```typescript
import { useState, useEffect, useContext } from "react";
import { FunctionComponent, ReactNode, MouseEvent } from "react";
```

For legacy CommonJS:

```javascript
const React = require("react");
```

## Basic Usage

```typescript
import React, { useState, MouseEvent } from "react";

// Function component with typed props
interface Props {
  name: string;
  age?: number;
  children: React.ReactNode;
}

const UserProfile: React.FunctionComponent<Props> = ({ name, age, children }) => {
  const [count, setCount] = useState<number>(0);

  const handleClick = (event: MouseEvent<HTMLButtonElement>) => {
    setCount(prev => prev + 1);
    console.log('Button clicked:', event.currentTarget);
  };

  return (
    <div>
      <h1>{name} {age && `(${age})`}</h1>
      <button onClick={handleClick}>Count: {count}</button>
      {children}
    </div>
  );
};

// Class component with typed props and state
interface State {
  loading: boolean;
}

class DataComponent extends React.Component<Props, State> {
  state: State = { loading: false };

  render(): React.ReactNode {
    return <div>{this.state.loading ? 'Loading...' : this.props.children}</div>;
  }
}
```

## Architecture

@types/react is built around several key type systems:

- **Component Types**: Type definitions for function and class components (`FunctionComponent`, `ComponentClass`)
- **Element System**: Types for React elements and renderable content (`ReactElement`, `ReactNode`)
- **Hook Types**: Complete type safety for all React hooks with proper generic inference
- **Event System**: Synthetic event types with DOM-specific event handling
- **JSX Integration**: Full JSX element typing with HTML and SVG attribute support
- **Ref System**: Type-safe ref handling for both object and callback refs
- **Context System**: Typed context creation and consumption patterns

## Capabilities

### Core React Functions

Essential React functions for creating and manipulating elements, the foundation of React development.

```typescript { .api }
function createElement<P extends HTMLAttributes<T>, T extends HTMLElement>(
  type: keyof ReactHTML,
  props?: ClassAttributes<T> & P | null,
  ...children: ReactNode[]
): DetailedReactHTMLElement<P, T>;

function createElement<P extends SVGAttributes<T>, T extends SVGElement>(
  type: keyof ReactSVG,
  props?: ClassAttributes<T> & P | null,
  ...children: ReactNode[]
): ReactSVGElement;

function createElement<P extends DOMAttributes<T>, T extends Element>(
  type: string,
  props?: ClassAttributes<T> & P | null,
  ...children: ReactNode[]
): DOMElement<P, T>;

function createElement<P extends {}>(
  type: FunctionComponent<P>,
  props?: Attributes & P | null,
  ...children: ReactNode[]
): FunctionComponentElement<P>;

function createElement<P extends {}>(
  type: ComponentClass<P>,
  props?: ClassAttributes<ComponentClass<P>> & P | null,
  ...children: ReactNode[]
): CElement<P, ComponentClass<P>>;

function cloneElement<P extends HTMLAttributes<T>, T extends HTMLElement>(
  element: DetailedReactHTMLElement<P, T>,
  props?: P,
  ...children: ReactNode[]
): DetailedReactHTMLElement<P, T>;

function cloneElement<P extends SVGAttributes<T>, T extends SVGElement>(
  element: ReactSVGElement,
  props?: P,
  ...children: ReactNode[]
): ReactSVGElement;

function cloneElement<P>(
  element: ReactElement<P>,
  props?: Partial<P> & Attributes,
  ...children: ReactNode[]
): ReactElement<P>;

function isValidElement<P>(object: {} | null | undefined): object is ReactElement<P>;

function createRef<T>(): RefObject<T>;

function lazy<T extends ComponentType<any>>(
  factory: () => Promise<{ default: T }>
): LazyExoticComponent<T>;

const Children: {
  map<T, C>(children: C | ReadonlyArray<C>, fn: (child: C, index: number) => T): C extends null | undefined ? C : Array<Exclude<T, boolean | null | undefined>>;
  forEach<C>(children: C | ReadonlyArray<C>, fn: (child: C, index: number) => void): void;
  count(children: any): number;
  only<C>(children: C): C extends any[] ? never : C;
  toArray(children: ReactNode | ReactNode[]): Array<Exclude<ReactNode, boolean | null | undefined>>;
};
```

### Built-in Components

React's built-in components for fragments, development tools, async boundaries, and performance profiling.

```typescript { .api }
const Fragment: ExoticComponent<{ children?: ReactNode }>;

const StrictMode: ExoticComponent<StrictModeProps>;

interface StrictModeProps {
  children?: ReactNode;
}

const Suspense: ExoticComponent<SuspenseProps>;

interface SuspenseProps {
  children?: ReactNode;
  fallback?: ReactNode;
}

const Profiler: ExoticComponent<ProfilerProps>;

interface ProfilerProps {
  children?: ReactNode;
  id: string;
  onRender: ProfilerOnRenderCallback;
}

type ProfilerOnRenderCallback = (
  id: string,
  phase: "mount" | "update" | "nested-update",
  actualDuration: number,
  baseDuration: number,
  startTime: number,
  commitTime: number,
  interactions: Set<SchedulerInteraction>
) => void;
```

### Component Types

Core component type definitions for building React applications with full type safety.

```typescript { .api }
interface FunctionComponent<P = {}> {
  (props: P): ReactNode | Promise<ReactNode>;
  displayName?: string;
  defaultProps?: Partial<P>;
}

interface ComponentClass<P = {}, S = ComponentState> {
  new (props: P, context?: any): Component<P, S>;
  displayName?: string;
  defaultProps?: Partial<P>;
  contextType?: Context<any>;
}

type ComponentType<P = {}> = ComponentClass<P> | FunctionComponent<P>;
```

[Components](./components.md)

### Element and Node Types

Type definitions for React elements and all renderable content in React applications.

```typescript { .api }
interface ReactElement<P = any, T extends string | JSXElementConstructor<any> = string | JSXElementConstructor<any>> {
  type: T;
  props: P;
  key: string | null;
}

type ReactNode = 
  | ReactElement 
  | string 
  | number 
  | bigint 
  | Iterable<ReactNode> 
  | ReactPortal 
  | boolean 
  | null 
  | undefined 
  | Promise<AwaitedReactNode>;

interface ReactPortal extends ReactElement {
  children: ReactNode;
}
```

[Elements](./elements.md)

### React Hooks

Complete type definitions for all React hooks with proper generic type inference and safety.

```typescript { .api }
function useState<S>(initialState: S | (() => S)): [S, Dispatch<SetStateAction<S>>];
function useState<S = undefined>(): [S | undefined, Dispatch<SetStateAction<S | undefined>>];

function useEffect(effect: EffectCallback, deps?: DependencyList): void;

function useContext<T>(context: Context<T>): T;

function useRef<T>(initialValue: T): MutableRefObject<T>;
function useRef<T>(initialValue: T | null): RefObject<T>;
function useRef<T = undefined>(): MutableRefObject<T | undefined>;
```

[Hooks](./hooks.md)

### Event System

Comprehensive event type definitions for handling DOM events in React with full type safety.

```typescript { .api }
interface SyntheticEvent<T = Element, E = Event> extends BaseSyntheticEvent<E, EventTarget & T, EventTarget> {}

interface MouseEvent<T = Element> extends SyntheticEvent<T, NativeMouseEvent> {
  button: number;
  buttons: number;
  clientX: number;
  clientY: number;
  ctrlKey: boolean;
  shiftKey: boolean;
  altKey: boolean;
  metaKey: boolean;
}

type MouseEventHandler<T = Element> = EventHandler<MouseEvent<T>>;
```

[Events](./events.md)

### Ref System

Type-safe ref handling for accessing DOM elements and component instances.

```typescript { .api }
interface RefObject<T> {
  readonly current: T | null;
}

interface MutableRefObject<T> {
  current: T;
}

type Ref<T> = RefCallback<T> | RefObject<T | null> | null;

type RefCallback<T> = (instance: T | null) => void | (() => void);

function createRef<T>(): RefObject<T | null>;

function forwardRef<T, P = {}>(
  render: ForwardRefRenderFunction<T, P>
): ForwardRefExoticComponent<PropsWithoutRef<P> & RefAttributes<T>>;
```

[Refs](./refs.md)

### Context API

Type definitions for React's Context API enabling type-safe data sharing across component trees.

```typescript { .api }
interface Context<T> {
  Provider: Provider<T>;
  Consumer: Consumer<T>;
  displayName?: string;
}

function createContext<T>(defaultValue: T): Context<T>;

interface Provider<T> {
  (props: ProviderProps<T>): ReactElement | null;
}

interface ProviderProps<T> {
  value: T;
  children?: ReactNode;
}
```

[Context](./context.md)

### Component Lifecycle

Type definitions for class component lifecycle methods and state management.

```typescript { .api }
abstract class Component<P = {}, S = {}, SS = any> {
  props: Readonly<P>;
  state: Readonly<S>;
  context: unknown;

  setState<K extends keyof S>(
    state: ((prevState: Readonly<S>, props: Readonly<P>) => Pick<S, K> | S | null) | Pick<S, K> | S | null,
    callback?: () => void
  ): void;

  forceUpdate(callback?: () => void): void;

  abstract render(): ReactNode;

  componentDidMount?(): void;
  componentWillUnmount?(): void;
  componentDidUpdate?(prevProps: Readonly<P>, prevState: Readonly<S>, snapshot?: SS): void;
  shouldComponentUpdate?(nextProps: Readonly<P>, nextState: Readonly<S>, nextContext: any): boolean;
}
```

[Lifecycle](./lifecycle.md)

### JSX Types

JSX element types and interfaces for type-safe JSX usage.

```typescript { .api }
declare global {
  namespace JSX {
    interface Element extends React.ReactElement<any, any> {}
    
    interface IntrinsicElements {
      div: React.DetailedHTMLProps<React.HTMLAttributes<HTMLDivElement>, HTMLDivElement>;
      span: React.DetailedHTMLProps<React.HTMLAttributes<HTMLSpanElement>, HTMLSpanElement>;
      button: React.DetailedHTMLProps<React.ButtonHTMLAttributes<HTMLButtonElement>, HTMLButtonElement>;
      // ... all HTML and SVG elements
    }

    interface ElementClass extends React.Component<any, any> {}
    interface ElementAttributesProperty { props: {}; }
    interface ElementChildrenAttribute { children: {}; }
  }
}
```

[JSX Types](./jsx.md)

### HTML and SVG Attributes

Comprehensive attribute type definitions for all HTML and SVG elements.

```typescript { .api }
interface HTMLAttributes<T> extends AriaAttributes, DOMAttributes<T> {
  className?: string;
  id?: string;
  style?: CSSProperties;
  title?: string;
  lang?: string;
  dir?: "ltr" | "rtl" | "auto";
  tabIndex?: number;
  role?: AriaRole;
}

interface SVGAttributes<T> extends AriaAttributes, DOMAttributes<T> {
  className?: string;
  id?: string;
  style?: CSSProperties;
  viewBox?: string;
  xmlns?: string;
}

interface AriaAttributes {
  "aria-label"?: string;
  "aria-labelledby"?: string;
  "aria-describedby"?: string;
  "aria-hidden"?: Booleanish;
  // ... all ARIA attributes
}
```

[HTML Attributes](./html-attributes.md)

### Utility Types

Powerful utility types for extracting and manipulating component and element types.

```typescript { .api }
type ComponentProps<T extends keyof JSX.IntrinsicElements | JSXElementConstructor<any>> =
  T extends JSXElementConstructor<infer P>
    ? P
    : T extends keyof JSX.IntrinsicElements
    ? JSX.IntrinsicElements[T]
    : {};

type PropsWithChildren<P = unknown> = P & { children?: ReactNode };

type ComponentPropsWithRef<T extends ElementType> = T extends new (props: infer P) => Component<any, any>
  ? PropsWithoutRef<P> & RefAttributes<InstanceType<T>>
  : ComponentProps<T>;

type ComponentRef<T extends ElementType> = T extends NamedExoticComponent<ComponentPropsWithoutRef<T> & RefAttributes<infer Method>>
  ? Method
  : ComponentPropsWithRef<T> extends RefAttributes<infer Method>
  ? Method
  : never;
```

[Utilities](./utilities.md)

### Experimental Features

Type definitions for experimental React features and canary builds.

```typescript { .api }
// Canary features
function unstable_useCacheRefresh(): () => void;

// Experimental features  
function experimental_useEffectEvent<T extends Function>(event: T): T;

function experimental_taintUniqueValue(
  message: string | undefined,
  lifetime: object,
  value: string | bigint
): void;

interface SuspenseProps {
  children?: ReactNode;
  fallback?: ReactNode;
  unstable_expectedLoadTime?: number; // Experimental
}
```

[Experimental](./experimental.md)

### Imperative APIs

Imperative functions for direct React control outside of components.

```typescript { .api }
function startTransition(scope: () => void): void;
```