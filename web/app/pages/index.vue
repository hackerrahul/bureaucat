<script setup lang="ts">
const { isAuthenticated } = useAuth();

if (import.meta.client && isAuthenticated.value) {
  navigateTo("/dashboard");
}

useSeoMeta({
  title: "AiGiny",
  description: "welcome to AiGiny",
});
</script>

<template>
  <div class="flex min-h-svh items-center justify-center bg-background">
    <h1 class="text-2xl font-medium tracking-tight text-foreground">
      welcome to AiGiny
    </h1>
  </div>
</template>
