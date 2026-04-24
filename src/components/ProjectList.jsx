import { useEffect, useRef, useState } from 'react'
import { DndContext, PointerSensor, closestCenter, useSensor, useSensors } from '@dnd-kit/core'
import { SortableContext, arrayMove, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'

const TYPE_LABELS = {
  lambda: 'λ Lambda',
  gitlab_cicd: '⎇ GitLab CI/CD',
}

const TYPE_COLORS = {
  lambda: '#ff9900',
  gitlab_cicd: '#fc6d26',
}

function projectDragId(projectId) {
  return `project:${projectId}`
}

function sourceDragId(projectId, sourceId) {
  return `source:${projectId}:${sourceId}`
}

function parseDragId(id) {
  const parts = String(id).split(':')
  if (parts[0] === 'project' && parts.length === 2) {
    return { kind: 'project', projectId: Number(parts[1]) }
  }
  if (parts[0] === 'source' && parts.length === 3) {
    return { kind: 'source', projectId: Number(parts[1]), sourceId: Number(parts[2]) }
  }
  return null
}

function DragHandle({ attributes, listeners }) {
  return (
    <button
      type="button"
      className="drag-handle"
      aria-label="Reorder"
      title="Drag to reorder"
      onClick={e => e.stopPropagation()}
      {...attributes}
      {...listeners}
    >
      ⋮⋮
    </button>
  )
}

function SortableProject({
  project,
  isOpen,
  isEditing,
  editing,
  inputRef,
  selectedSourceId,
  onToggle,
  onStartEdit,
  onCommitEdit,
  onSetEditing,
  onDeleteProject,
  onSelectSource,
  onRenameSource,
  onDeleteSource,
  onAddSource,
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: projectDragId(project.id) })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  }

  const sourceItems = project.sources.map(source => sourceDragId(project.id, source.id))

  return (
    <div ref={setNodeRef} style={style} className={`project-group ${isDragging ? 'dragging' : ''}`}>
      <div
        className={`project-header ${isOpen ? 'open' : ''}`}
        onClick={() => !isEditing && onToggle(project.id)}
      >
        <DragHandle attributes={attributes} listeners={listeners} />
        <span className={`project-chevron ${isOpen ? 'open' : ''}`}>▸</span>
        {isEditing ? (
          <input
            ref={inputRef}
            className="source-name-input"
            value={editing.value}
            onChange={e => onSetEditing({ ...editing, value: e.target.value })}
            onBlur={onCommitEdit}
            onKeyDown={e => {
              if (e.key === 'Enter') onCommitEdit()
              if (e.key === 'Escape') onSetEditing(null)
            }}
            onClick={e => e.stopPropagation()}
          />
        ) : (
          <span
            className="project-name"
            onDoubleClick={e => {
              e.stopPropagation()
              onStartEdit('project', project.id, project.name)
            }}
            title="Double-click to rename"
          >
            {project.name}
          </span>
        )}
        <span className="project-count">{project.sources.length}</span>
        <button
          className="btn-delete-source btn-delete-project"
          onClick={e => {
            e.stopPropagation()
            if (confirm(`Delete project "${project.name}" and all its sources?`)) {
              onDeleteProject(project.id)
            }
          }}
          title="Delete project"
        >
          ×
        </button>
      </div>

      {isOpen && (
        <div className="project-body">
          <SortableContext items={sourceItems} strategy={verticalListSortingStrategy}>
            {project.sources.map(source => {
              const isEditingSource = editing?.kind === 'source' && editing.id === source.id
              return (
                <SortableSource
                  key={source.id}
                  projectId={project.id}
                  source={source}
                  selected={selectedSourceId === source.id}
                  isEditing={isEditingSource}
                  editing={editing}
                  inputRef={inputRef}
                  onSelectSource={onSelectSource}
                  onStartEdit={onStartEdit}
                  onCommitEdit={onCommitEdit}
                  onSetEditing={onSetEditing}
                  onDeleteSource={onDeleteSource}
                />
              )
            })}
          </SortableContext>
          <button
            className="btn-add-source-inline"
            onClick={() => onAddSource(project.id)}
          >
            + Add Source
          </button>
        </div>
      )}
    </div>
  )
}

function SortableSource({
  projectId,
  source,
  selected,
  isEditing,
  editing,
  inputRef,
  onSelectSource,
  onStartEdit,
  onCommitEdit,
  onSetEditing,
  onDeleteSource,
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: sourceDragId(projectId, source.id) })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`source-item ${selected ? 'active' : ''} ${isDragging ? 'dragging' : ''}`}
      onClick={() => !isEditing && onSelectSource(source)}
    >
      <DragHandle attributes={attributes} listeners={listeners} />
      <div className="source-info">
        <span className="source-badge" style={{ color: TYPE_COLORS[source.type] }}>
          {TYPE_LABELS[source.type] || source.type}
        </span>
        {isEditing ? (
          <input
            ref={inputRef}
            className="source-name-input"
            value={editing.value}
            onChange={e => onSetEditing({ ...editing, value: e.target.value })}
            onBlur={onCommitEdit}
            onKeyDown={e => {
              if (e.key === 'Enter') onCommitEdit()
              if (e.key === 'Escape') onSetEditing(null)
            }}
            onClick={e => e.stopPropagation()}
          />
        ) : (
          <span
            className="source-name"
            onDoubleClick={e => {
              e.stopPropagation()
              onStartEdit('source', source.id, source.name)
            }}
            title="Double-click to rename"
          >
            {source.name}
          </span>
        )}
      </div>
      <button
        className="btn-delete-source"
        onClick={e => {
          e.stopPropagation()
          if (confirm(`Delete source "${source.name}"?`)) onDeleteSource(source.id)
        }}
        title="Delete source"
      >
        ×
      </button>
    </div>
  )
}

export default function ProjectList({
  projects,
  selectedSourceId,
  onSelectSource,
  onRenameProject,
  onDeleteProject,
  onReorderProjects,
  onRenameSource,
  onDeleteSource,
  onReorderSources,
  onAddSource,
}) {
  const [expanded, setExpanded] = useState(() => new Set(projects.map(p => p.id)))
  const [editing, setEditing] = useState(null)
  const inputRef = useRef(null)
  const lastEditingKeyRef = useRef(null)

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 6 },
    })
  )

  useEffect(() => {
    if (!editing) {
      lastEditingKeyRef.current = null
      return
    }

    const editingKey = `${editing.kind}:${editing.id}`
    if (lastEditingKeyRef.current === editingKey) return

    lastEditingKeyRef.current = editingKey
    inputRef.current?.focus()
    inputRef.current?.select()
  }, [editing])

  useEffect(() => {
    setExpanded(prev => {
      const next = new Set(prev)
      projects.forEach(p => next.add(p.id))
      return next
    })
  }, [projects.length])

  function toggle(id) {
    setExpanded(prev => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  function startEdit(kind, id, value) {
    setEditing({ kind, id, value })
  }

  function commitEdit() {
    if (!editing) return
    const trimmed = editing.value.trim()
    if (trimmed) {
      if (editing.kind === 'project') onRenameProject(editing.id, trimmed)
      else onRenameSource(editing.id, trimmed)
    }
    setEditing(null)
  }

  function handleDragEnd(event) {
    const active = parseDragId(event.active?.id)
    const over = parseDragId(event.over?.id)

    if (!active || !over) return

    if (active.kind === 'project' && over.kind === 'project' && active.projectId !== over.projectId) {
      const projectIds = projects.map(project => project.id)
      const oldIndex = projectIds.indexOf(active.projectId)
      const newIndex = projectIds.indexOf(over.projectId)
      if (oldIndex !== -1 && newIndex !== -1 && oldIndex !== newIndex) {
        onReorderProjects(arrayMove(projectIds, oldIndex, newIndex))
      }
      return
    }

    if (
      active.kind === 'source' &&
      over.kind === 'source' &&
      active.projectId === over.projectId &&
      active.sourceId !== over.sourceId
    ) {
      const project = projects.find(item => item.id === active.projectId)
      if (!project) return
      const sourceIds = project.sources.map(source => source.id)
      const oldIndex = sourceIds.indexOf(active.sourceId)
      const newIndex = sourceIds.indexOf(over.sourceId)
      if (oldIndex !== -1 && newIndex !== -1 && oldIndex !== newIndex) {
        onReorderSources(active.projectId, arrayMove(sourceIds, oldIndex, newIndex))
      }
    }
  }

  if (projects.length === 0) {
    return (
      <div className="project-list">
        <p className="source-empty">
          No projects yet.<br />
          Click "+ Add Project" to get started.
        </p>
      </div>
    )
  }

  return (
    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
      <div className="project-list">
        <SortableContext
          items={projects.map(project => projectDragId(project.id))}
          strategy={verticalListSortingStrategy}
        >
          {projects.map(project => (
            <SortableProject
              key={project.id}
              project={project}
              isOpen={expanded.has(project.id)}
              isEditing={editing?.kind === 'project' && editing.id === project.id}
              editing={editing}
              inputRef={inputRef}
              selectedSourceId={selectedSourceId}
              onToggle={toggle}
              onStartEdit={startEdit}
              onCommitEdit={commitEdit}
              onSetEditing={setEditing}
              onDeleteProject={onDeleteProject}
              onSelectSource={onSelectSource}
              onRenameSource={onRenameSource}
              onDeleteSource={onDeleteSource}
              onAddSource={onAddSource}
            />
          ))}
        </SortableContext>
      </div>
    </DndContext>
  )
}
