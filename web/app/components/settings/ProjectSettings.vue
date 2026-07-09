<script setup lang="ts">
import { Loader2 } from "lucide-vue-next";
import { toast } from "vue-sonner";
import type { Project, MoveImpactMember } from "~/types";

const props = defineProps<{
  project: Project;
  isAdmin: boolean;
}>();

const emit = defineEmits<{
  refresh: [];
}>();

const { updateProject, getMoveProjectImpact, moveProjectToWorkspace, setProjectDisabled } =
  useProjects();
const { user } = useAuth();
const { workspaces, listWorkspaces } = useWorkspaces();

const loading = ref(false);
const togglingDisabled = ref(false);
const movingWorkspace = ref(false);

// Only global admins may reassign a project's workspace (server-enforced).
const isGlobalAdmin = computed(() => user.value?.user_type === "admin");

// The workspace the project currently belongs to.
const currentWorkspace = computed(() =>
  workspaces.value.find((w) => w.id === props.project.workspace_id) ?? null
);

// Bound to the workspace <select>; defaults to the current workspace.
const selectedWorkspaceId = ref(props.project.workspace_id);

watch(
  () => props.project.workspace_id,
  (id) => {
    selectedWorkspaceId.value = id;
  }
);

const workspaceChanged = computed(
  () => selectedWorkspaceId.value !== props.project.workspace_id
);

onMounted(() => {
  if (workspaces.value.length === 0) listWorkspaces();
});

// Move confirmation dialog state. Opening the dialog previews which members
// would lose visibility of the project in the destination workspace.
const showMoveDialog = ref(false);
const loadingImpact = ref(false);
const impactMembers = ref<MoveImpactMember[]>([]);
const addMembers = ref(true);

// The workspace selected in the <select>, resolved to a full object.
const pendingTarget = computed(() =>
  workspaces.value.find((w) => w.id === selectedWorkspaceId.value) ?? null
);

async function openMoveDialog() {
  if (!pendingTarget.value || !workspaceChanged.value) return;

  showMoveDialog.value = true;
  loadingImpact.value = true;
  impactMembers.value = [];
  addMembers.value = true;

  const result = await getMoveProjectImpact(
    props.project.project_key,
    pendingTarget.value.workspace_key
  );
  loadingImpact.value = false;

  if (result.success && result.data) {
    impactMembers.value = result.data.members;
  } else {
    toast.error(result.error || "Failed to load move impact");
  }
}

async function confirmMove() {
  const target = pendingTarget.value;
  if (!target) return;

  // Only pass the flag when there are members to add and the admin opted in.
  const shouldAddMembers = impactMembers.value.length > 0 && addMembers.value;

  movingWorkspace.value = true;
  const result = await moveProjectToWorkspace(
    props.project.project_key,
    target.workspace_key,
    shouldAddMembers
  );
  movingWorkspace.value = false;
  showMoveDialog.value = false;

  if (result.success) {
    const added = shouldAddMembers ? impactMembers.value.length : 0;
    toast.success(
      added > 0
        ? `Moved to "${target.name}" and added ${added} member${added === 1 ? "" : "s"}`
        : `Moved to "${target.name}"`
    );
    emit("refresh");
  } else {
    selectedWorkspaceId.value = props.project.workspace_id;
    toast.error(result.error || "Failed to move project");
  }
}

async function handleToggleDisabled(disabled: boolean) {
  togglingDisabled.value = true;
  const result = await setProjectDisabled(props.project.project_key, disabled);
  togglingDisabled.value = false;

  if (result.success) {
    toast.success(disabled ? "Project disabled" : "Project enabled");
    emit("refresh");
  } else {
    toast.error(result.error || "Failed to update project");
  }
}

const form = ref({
  name: props.project.name,
  description: props.project.description || "",
});

watch(
  () => props.project,
  (p) => {
    form.value = {
      name: p.name,
      description: p.description || "",
    };
  },
  { immediate: true }
);

async function handleSave() {
  loading.value = true;
  const result = await updateProject(props.project.project_key, {
    name: form.value.name,
    description: form.value.description || undefined,
  });
  loading.value = false;

  if (result.success) {
    toast.success("Project updated");
    emit("refresh");
  } else {
    toast.error(result.error || "Failed to update project");
  }
}

const hasChanges = computed(() => {
  return (
    form.value.name !== props.project.name ||
    form.value.description !== (props.project.description || "")
  );
});
</script>

<template>
  <div class="space-y-8">
    <!-- General settings -->
    <div class="space-y-4">
      <div>
        <h3 class="font-semibold">General</h3>
        <p class="text-sm text-muted-foreground">
          Basic project information
        </p>
      </div>

      <Card>
        <CardContent class="pt-6">
          <form class="space-y-4" @submit.prevent="handleSave">
            <div class="space-y-2">
              <Label for="project-key">Project Key</Label>
              <input
                id="project-key"
                :value="project.project_key"
                disabled
                class="border-input dark:bg-input/30 h-9 w-full rounded-md border bg-transparent px-3 py-1 font-mono text-base shadow-xs disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 md:text-sm"
              />
              <p class="text-xs text-muted-foreground">
                Cannot be changed after creation
              </p>
            </div>

            <div class="space-y-2">
              <Label for="name">Name</Label>
              <Input
                id="name"
                v-model="form.name"
                :disabled="loading || !isAdmin || project.disabled"
              />
            </div>

            <div class="space-y-2">
              <Label for="description">Description</Label>
              <Textarea
                id="description"
                v-model="form.description"
                rows="3"
                :disabled="loading || !isAdmin || project.disabled"
              />
            </div>

            <div v-if="isAdmin" class="flex justify-end">
              <Button type="submit" :disabled="loading || !hasChanges || project.disabled">
                <Loader2 v-if="loading" class="mr-2 size-4 animate-spin" />
                Save Changes
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>

    <!-- Workspace -->
    <div class="space-y-4">
      <div>
        <h3 class="font-semibold">Workspace</h3>
        <p class="text-sm text-muted-foreground">
          The workspace this project belongs to
        </p>
      </div>

      <Card>
        <CardContent class="pt-6">
          <template v-if="isGlobalAdmin">
            <div class="space-y-2">
              <Label for="workspace">Workspace</Label>
              <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
                <Select v-model="selectedWorkspaceId" :disabled="movingWorkspace">
                  <SelectTrigger id="workspace" class="w-full sm:max-w-xs">
                    <SelectValue placeholder="Select a workspace" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem v-for="w in workspaces" :key="w.id" :value="w.id">
                      {{ w.name }}
                    </SelectItem>
                  </SelectContent>
                </Select>
                <Button
                  variant="outline"
                  :disabled="!workspaceChanged || movingWorkspace"
                  @click="openMoveDialog"
                >
                  Move
                </Button>
              </div>
              <p class="text-xs text-muted-foreground">
                Moving only changes which workspace the project lives in; project
                membership is unchanged. Members who aren't in the target workspace
                won't see it in that workspace's project list.
              </p>
            </div>

            <!-- Move confirmation with visibility-impact preview -->
            <Dialog v-model:open="showMoveDialog">
              <DialogContent class="max-h-[85vh] overflow-y-auto sm:max-w-md">
                <DialogHeader>
                  <DialogTitle>Move to "{{ pendingTarget?.name }}"</DialogTitle>
                  <DialogDescription>
                    Project membership and roles are unchanged by the move.
                  </DialogDescription>
                </DialogHeader>

                <div class="space-y-4 py-2">
                  <div v-if="loadingImpact" class="flex items-center gap-2 text-sm text-muted-foreground">
                    <Loader2 class="size-4 animate-spin" />
                    Checking who's affected…
                  </div>

                  <template v-else>
                    <p v-if="impactMembers.length === 0" class="text-sm text-muted-foreground">
                      All project members are already in this workspace. Nothing else
                      changes.
                    </p>

                    <template v-else>
                      <p class="text-sm">
                        <span class="font-medium">{{ impactMembers.length }}</span>
                        member{{ impactMembers.length === 1 ? "" : "s" }} aren't in
                        "{{ pendingTarget?.name }}" and would lose sight of this project
                        in that workspace's list.
                      </p>

                      <div class="max-h-48 overflow-y-auto rounded-md border">
                        <ul class="divide-y">
                          <li
                            v-for="m in impactMembers"
                            :key="m.user_id"
                            class="px-3 py-2 text-sm"
                          >
                            <span class="font-medium">{{ m.first_name }} {{ m.last_name }}</span>
                            <span class="break-all text-muted-foreground"> · {{ m.email }}</span>
                          </li>
                        </ul>
                      </div>

                      <label class="flex items-start gap-2 text-sm">
                        <Checkbox v-model="addMembers" class="mt-0.5" />
                        <span>
                          Also add {{ impactMembers.length === 1 ? "this member" : "these members" }}
                          to "{{ pendingTarget?.name }}" so they keep access.
                        </span>
                      </label>
                    </template>
                  </template>
                </div>

                <DialogFooter>
                  <Button variant="outline" :disabled="movingWorkspace" @click="showMoveDialog = false">
                    Cancel
                  </Button>
                  <Button :disabled="movingWorkspace || loadingImpact" @click="confirmMove">
                    <Loader2 v-if="movingWorkspace" class="mr-2 size-4 animate-spin" />
                    Move project
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </template>
          <template v-else>
            <div class="flex items-center justify-between gap-4">
              <div class="space-y-1">
                <Label>Workspace</Label>
                <p class="text-sm text-muted-foreground">
                  Only a global admin can move this project to another workspace.
                </p>
              </div>
              <span class="text-sm font-medium">{{ currentWorkspace?.name || "—" }}</span>
            </div>
          </template>
        </CardContent>
      </Card>
    </div>

    <!-- Availability -->
    <div v-if="isAdmin" class="space-y-4">
      <div>
        <h3 class="font-semibold">Availability</h3>
        <p class="text-sm text-muted-foreground">
          Disable the project to make it read-only
        </p>
      </div>

      <Card>
        <CardContent class="flex items-center justify-between gap-4 pt-6">
          <div class="space-y-1">
            <Label>Disable project</Label>
            <p class="text-sm text-muted-foreground">
              When disabled, the project becomes read-only: no tasks can be
              created, edited, moved, or commented on until it is re-enabled.
            </p>
          </div>
          <Switch
            :checked="project.disabled"
            :disabled="togglingDisabled"
            aria-label="Disable project"
            @update:checked="handleToggleDisabled"
          />
        </CardContent>
      </Card>
    </div>

  </div>
</template>
