// Re-exports the single theme HELIOS uses. Importing 'survey-core/themes'
// directly from a dynamic import() would materialise the whole module
// namespace, including the barrel's aggregate default export — an object that
// references all 33 shipped themes. Narrowing the namespace to one named
// export lets Rolldown tree-shake the other 32 away.
export { BorderlessDark } from 'survey-core/themes';
